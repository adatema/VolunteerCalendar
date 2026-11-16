/**
 * Elevated-access helper for the volunteer shift calendar.
 *
 * Runs without sharing and in system mode on purpose, so volunteers on any user license can use the
 * calendar without being granted object permissions that some licenses (for example High Volume
 * Customer Portal) do not allow. Volunteers reach this class only through VolunteerCalendarController,
 * which they can run only when the Volunteer Calendar Access permission set gives them class access.
 *
 * Every input comes from the server, never the browser. Shift reads are limited to shifts that are
 * published, have a position, are active, and are upcoming. Nothing here returns other volunteers' data.
 */
public without sharing class VolunteerCalendarAccessHelper {
    private static final String FALLBACK_TIME_ZONE = 'GMT';
    private static final String SHIFT_FIELDS =
        'Id, Description, StartDate, StartTime, EndDate, EndTime, TimeZone, MaximumAttendeesCount, JobPositionId, ' +
        'JobPosition.Title, JobPosition.Calendar_Color__c, JobPosition.VolunteerInitiativeId, JobPosition.VolunteerInitiative.Name';
    private static final String OPEN_SHIFT_FILTER =
        'Published__c = true AND JobPositionId != null AND Status IN :activeStatuses AND StartDate >= :today ' +
        'AND StartTime != null AND EndDate != null AND EndTime != null';
    private static String companyTimeZoneName;

    /**
     * Reads the company's default time zone.
     * @return The time zone ID, for example America/Los_Angeles.
     */
    public static String getCompanyTimeZoneName() {
        if (companyTimeZoneName == null) {
            List<Organization> organizations = [SELECT TimeZoneSidKey FROM Organization WITH SYSTEM_MODE LIMIT 1];
            companyTimeZoneName = organizations.isEmpty() ? FALLBACK_TIME_ZONE : organizations[0].TimeZoneSidKey;
        }
        return companyTimeZoneName;
    }

    /**
     * Finds the logged-in user's Account and Contact.
     * @param userId The logged-in user's Id, taken from the server.
     * @return The volunteer identity. Both Ids are blank when the user has no Account.
     */
    public static VolunteerCalendarService.VolunteerIdentity getVolunteerIdentity(Id userId) {
        VolunteerCalendarService.VolunteerIdentity identity = new VolunteerCalendarService.VolunteerIdentity();
        List<User> users = [SELECT AccountId, ContactId FROM User WHERE Id = :userId WITH SYSTEM_MODE LIMIT 1];
        if (!users.isEmpty()) {
            identity.accountId = users[0].AccountId;
            identity.contactId = users[0].ContactId;
        }
        return identity;
    }

    /**
     * Lists the published, active shifts that start in a date range.
     * @param rangeStart First start date to include.
     * @param rangeEnd Last start date to include.
     * @param activeStatuses The shift statuses that count as active.
     * @return Matching shifts, earliest first.
     */
    public static List<JobPositionShift> getCalendarShifts(Date rangeStart, Date rangeEnd, Set<String> activeStatuses) {
        Date today = Date.today();
        Date lowerBound = rangeStart > today ? rangeStart : today;
        return [
            SELECT Id, Description, StartDate, StartTime, EndDate, EndTime, TimeZone, MaximumAttendeesCount, JobPositionId,
                   JobPosition.Title, JobPosition.Calendar_Color__c, JobPosition.VolunteerInitiativeId, JobPosition.VolunteerInitiative.Name
            FROM JobPositionShift
            WHERE Published__c = true AND JobPositionId != null AND Status IN :activeStatuses
              AND StartDate >= :lowerBound AND StartDate <= :rangeEnd
              AND StartTime != null AND EndDate != null AND EndTime != null
            WITH SYSTEM_MODE
            ORDER BY StartDate, StartTime
            LIMIT 2000
        ];
    }

    /**
     * Lists every published, active, upcoming shift, for building the filter drop-downs.
     * @param activeStatuses The shift statuses that count as active.
     * @return Matching shifts with their position and initiative names.
     */
    public static List<JobPositionShift> getUpcomingShiftsForFilters(Set<String> activeStatuses) {
        Date today = Date.today();
        return [
            SELECT JobPositionId, JobPosition.Title, JobPosition.VolunteerInitiativeId, JobPosition.VolunteerInitiative.Name
            FROM JobPositionShift
            WHERE Published__c = true AND JobPositionId != null AND Status IN :activeStatuses AND StartDate >= :today
              AND StartTime != null AND EndDate != null AND EndTime != null
            WITH SYSTEM_MODE
            LIMIT 5000
        ];
    }

    /**
     * Loads one shift only if it is still published, active, and upcoming.
     * @param shiftId The shift.
     * @param activeStatuses The shift statuses that count as active.
     * @param lockRecord True to lock the shift until the transaction ends, so two sign-ups cannot take the last spot.
     * @return A list with the shift, or an empty list when it is not open.
     */
    public static List<JobPositionShift> getOpenShift(Id shiftId, Set<String> activeStatuses, Boolean lockRecord) {
        String soql = 'SELECT ' + SHIFT_FIELDS + ' FROM JobPositionShift WHERE Id = :shiftId AND ' + OPEN_SHIFT_FILTER + ' LIMIT 1';
        if (lockRecord) {
            soql += ' FOR UPDATE';
        }
        Map<String, Object> binds = new Map<String, Object>{
            'shiftId' => shiftId,
            'today' => Date.today(),
            'activeStatuses' => activeStatuses
        };
        return Database.queryWithBinds(soql, binds, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Lists the qualifications a position requires.
     * @param positionId The Job Position.
     * @return The position's qualifications.
     */
    public static List<JobPositionQualification> getPositionQualifications(Id positionId) {
        return [
            SELECT QualificationReferenceRecordId
            FROM JobPositionQualification
            WHERE JobPositionId = :positionId
            WITH SYSTEM_MODE
            ORDER BY Name
        ];
    }

    /**
     * Counts the assignments that use up capacity on each shift (everything except canceled).
     * @param shiftIds The shifts to count.
     * @return Assignment counts by shift Id. Shifts with none are not in the map.
     */
    public static Map<Id, Integer> countActiveAssignments(Set<Id> shiftIds) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (shiftIds == null || shiftIds.isEmpty()) {
            return counts;
        }
        String canceledStatus = VolunteerCalendarService.STATUS_CANCELED;
        List<AggregateResult> rows = [
            SELECT AssignedPositionShiftId shiftId, COUNT(Id) total
            FROM JobPositionAssignment
            WHERE AssignedPositionShiftId IN :shiftIds AND Status != :canceledStatus
            WITH SYSTEM_MODE
            GROUP BY AssignedPositionShiftId
        ];
        for (AggregateResult row : rows) {
            counts.put((Id) row.get('shiftId'), (Integer) row.get('total'));
        }
        return counts;
    }

    /**
     * Checks whether the volunteer already has a non-canceled assignment for the shift.
     * @param shiftId The shift.
     * @param accountId The volunteer's Account.
     * @return True when the volunteer is already signed up.
     */
    public static Boolean hasActiveAssignment(Id shiftId, Id accountId) {
        if (shiftId == null || accountId == null) {
            return false;
        }
        String canceledStatus = VolunteerCalendarService.STATUS_CANCELED;
        return ![
            SELECT Id
            FROM JobPositionAssignment
            WHERE AssignedPositionShiftId = :shiftId AND AssignedAccountId = :accountId AND Status != :canceledStatus
            WITH SYSTEM_MODE
            LIMIT 1
        ].isEmpty();
    }

    /**
     * Looks up the display names of Competency and Examination records.
     * @param competencyIds Competency Ids.
     * @param examinationIds Examination Ids.
     * @return Names by record Id.
     */
    public static Map<Id, String> getQualificationNames(Set<Id> competencyIds, Set<Id> examinationIds) {
        Map<Id, String> names = new Map<Id, String>();
        if (competencyIds != null && !competencyIds.isEmpty()) {
            List<Competency> competencies = [SELECT Id, Name FROM Competency WHERE Id IN :competencyIds WITH SYSTEM_MODE];
            for (Competency record : competencies) {
                names.put(record.Id, record.Name);
            }
        }
        if (examinationIds != null && !examinationIds.isEmpty()) {
            List<Examination> examinations = [SELECT Id, Name FROM Examination WHERE Id IN :examinationIds WITH SYSTEM_MODE];
            for (Examination record : examinations) {
                names.put(record.Id, record.Name);
            }
        }
        return names;
    }

    /**
     * Reads the volunteer's own Person Competency records for the given competencies.
     * @param accountIds The volunteer's Account Ids.
     * @param contactIds The volunteer's Contact Ids.
     * @param competencyIds The competencies to look for.
     * @return Matching Person Competency records.
     */
    public static List<PersonCompetency> getPersonCompetencies(Set<Id> accountIds, Set<Id> contactIds, Set<Id> competencyIds) {
        Set<Id> personIds = new Set<Id>();
        personIds.addAll(accountIds);
        personIds.addAll(contactIds);
        if (personIds.isEmpty() || competencyIds == null || competencyIds.isEmpty()) {
            return new List<PersonCompetency>();
        }
        return [
            SELECT Id, CompetencyId, EffectiveStartDate, EffectiveEndDate
            FROM PersonCompetency
            WHERE PersonId IN :personIds AND CompetencyId IN :competencyIds
            WITH SYSTEM_MODE
        ];
    }

    /**
     * Reads the volunteer's own Person Examination records for the given examinations.
     * @param accountIds The volunteer's Account Ids.
     * @param contactIds The volunteer's Contact Ids.
     * @param examinationIds The examinations to look for.
     * @return Matching Person Examination records.
     */
    public static List<PersonExamination> getPersonExaminations(Set<Id> accountIds, Set<Id> contactIds, Set<Id> examinationIds) {
        if ((accountIds.isEmpty() && contactIds.isEmpty()) || examinationIds == null || examinationIds.isEmpty()) {
            return new List<PersonExamination>();
        }
        return [
            SELECT Id, ExaminationId, EffectiveFrom, EffectiveTo
            FROM PersonExamination
            WHERE ExaminationId IN :examinationIds AND (AccountId IN :accountIds OR ContactId IN :contactIds)
            WITH SYSTEM_MODE
        ];
    }

    /**
     * Creates the volunteer's assignment after the service has passed every check.
     * @param assignment The assignment to insert.
     */
    public static void createAssignment(JobPositionAssignment assignment) {
        insert as system assignment;
    }
}
