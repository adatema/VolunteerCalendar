/**
 * Business logic for the volunteer shift calendar: which shifts to show, whether a volunteer is
 * qualified, and the sign-up itself. The browser is never trusted for any of these checks.
 */
public with sharing class VolunteerCalendarService {
    public static final String STATUS_UPCOMING = 'Upcoming';
    public static final String STATUS_IN_PROGRESS = 'In Progress';
    public static final String STATUS_CANCELED = 'Canceled';

    public static final String QUALIFICATION_MET = 'Met';
    public static final String QUALIFICATION_NOT_MET = 'Not met';
    public static final String QUALIFICATION_EXPIRED = 'Expired';

    public static final String MSG_NO_ACCOUNT = 'We could not find your volunteer profile, so you cannot sign up yet. Please contact your organizer.';
    public static final String MSG_SHIFT_UNAVAILABLE = 'This shift is no longer open for sign-up.';
    public static final String MSG_ALREADY_SIGNED_UP = 'You are already signed up for this shift.';
    public static final String MSG_SHIFT_FULL = 'Sorry, this shift is full.';
    public static final String MSG_MISSING_PREFIX = 'You cannot sign up for this shift yet. Missing qualifications: ';
    public static final String MSG_BAD_DATES = 'Please choose a valid range of dates to show.';

    private static final Set<String> ACTIVE_SHIFT_STATUSES = new Set<String>{ STATUS_UPCOMING, STATUS_IN_PROGRESS };
    private static final List<String> COLOR_PALETTE = new List<String>{ 'Blue', 'Green', 'Orange', 'Purple', 'Teal' };
    private static final Integer MAX_RANGE_DAYS = 62;
    private static final String TYPE_COMPETENCY = 'Competency';
    private static final String TYPE_EXAMINATION = 'Examination';


    @TestVisible
    private static VolunteerIdentity testIdentity;

    /** Raised for problems that have a plain-language message the volunteer can read. */
    public class CalendarException extends Exception {
    }

    /** The logged-in volunteer's Account and Contact. */
    public class VolunteerIdentity {
        public Id accountId;
        public Id contactId;
    }

    /** One drop-down choice in a filter. */
    public class OptionDto implements Comparable {
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String label;

        public Integer compareTo(Object other) {
            return (label ?? '').compareTo(((OptionDto) other).label ?? '');
        }
    }

    /** The choices for the Position and Volunteer Initiative filters. */
    public class FilterOptionsDto {
        @AuraEnabled
        public List<OptionDto> positions = new List<OptionDto>();
        @AuraEnabled
        public List<OptionDto> initiatives = new List<OptionDto>();
    }

    /** A shift as shown on the calendar. */
    public class ShiftDto {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Id positionId;
        @AuraEnabled
        public String positionName;
        @AuraEnabled
        public Id initiativeId;
        @AuraEnabled
        public String initiativeName;
        @AuraEnabled
        public String color;
        @AuraEnabled
        public String startDateTime;
        @AuraEnabled
        public String endDateTime;
        @AuraEnabled
        public Integer maximumAttendees;
        @AuraEnabled
        public Integer remainingCapacity;
        @AuraEnabled
        public Boolean isUnlimited;
        @AuraEnabled
        public Boolean isFull;
    }

    /** One qualification on the shift's position and whether the volunteer meets it. */
    public class QualificationDto {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String qualificationType;
        @AuraEnabled
        public String status;
        public Id referenceId;
    }

    /** Everything the shift details pop-up needs. */
    public class ShiftDetailDto {
        @AuraEnabled
        public ShiftDto shift;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public List<QualificationDto> qualifications = new List<QualificationDto>();
        @AuraEnabled
        public String blockedMessage;
        @AuraEnabled
        public Boolean alreadySignedUp = false;
        @AuraEnabled
        public Boolean canSignUp = false;
    }

    /**
     * Lists the published, active, upcoming shifts that start in a date range.
     * @param rangeStart First day to include.
     * @param rangeEnd Last day to include.
     * @return Shifts for the calendar, earliest first.
     */
    public static List<ShiftDto> getShifts(Date rangeStart, Date rangeEnd) {
        if (rangeStart == null || rangeEnd == null || rangeEnd < rangeStart || rangeStart.daysBetween(rangeEnd) > MAX_RANGE_DAYS) {
            throw new CalendarException(MSG_BAD_DATES);
        }
        List<JobPositionShift> shifts = VolunteerCalendarAccessHelper.getCalendarShifts(rangeStart, rangeEnd, ACTIVE_SHIFT_STATUSES);
        Set<Id> shiftIds = new Map<Id, JobPositionShift>(shifts).keySet();
        Map<Id, Integer> assignmentCounts = VolunteerCalendarAccessHelper.countActiveAssignments(shiftIds);
        List<ShiftDto> result = new List<ShiftDto>();
        for (JobPositionShift shift : shifts) {
            result.add(toShiftDto(shift, assignmentCounts.get(shift.Id) ?? 0));
        }
        return result;
    }

    /**
     * Builds the Position and Volunteer Initiative filter choices from all upcoming published shifts.
     * @return The filter choices, sorted by name.
     */
    public static FilterOptionsDto getFilterOptions() {
        Map<Id, String> positions = new Map<Id, String>();
        Map<Id, String> initiatives = new Map<Id, String>();
        List<JobPositionShift> upcomingShifts = VolunteerCalendarAccessHelper.getUpcomingShiftsForFilters(ACTIVE_SHIFT_STATUSES);
        for (JobPositionShift shift : upcomingShifts) {
            positions.put(shift.JobPositionId, shift.JobPosition.Title);
            if (shift.JobPosition.VolunteerInitiativeId != null) {
                initiatives.put(shift.JobPosition.VolunteerInitiativeId, shift.JobPosition.VolunteerInitiative.Name);
            }
        }
        FilterOptionsDto options = new FilterOptionsDto();
        options.positions = toSortedOptions(positions);
        options.initiatives = toSortedOptions(initiatives);
        return options;
    }

    /**
     * Gets the details, qualifications, and sign-up state of one shift for the logged-in volunteer.
     * @param shiftId The shift.
     * @return The pop-up details.
     */
    public static ShiftDetailDto getShiftDetail(Id shiftId) {
        JobPositionShift shift = loadOpenShift(shiftId, false);
        return buildDetail(shift, getIdentity());
    }

    /**
     * Signs the logged-in volunteer up for a shift after re-checking everything on the server.
     * The shift record is locked so two people cannot take the last spot at the same moment.
     * @param shiftId The shift.
     * @return The refreshed pop-up details, now in the signed-up state.
     */
    public static ShiftDetailDto signUp(Id shiftId) {
        VolunteerIdentity identity = getIdentity();
        if (identity.accountId == null) {
            throw new CalendarException(MSG_NO_ACCOUNT);
        }
        JobPositionShift shift = loadOpenShift(shiftId, true);
        if (VolunteerCalendarAccessHelper.hasActiveAssignment(shift.Id, identity.accountId)) {
            throw new CalendarException(MSG_ALREADY_SIGNED_UP);
        }
        Datetime startAt = toInstant(shift.StartDate, shift.StartTime, shift.TimeZone);
        Datetime endAt = toInstant(shift.EndDate, shift.EndTime, shift.TimeZone);
        List<String> missing = missingNames(evaluateQualifications(shift.JobPositionId, identity, shift.StartDate, startAt));
        if (!missing.isEmpty()) {
            throw new CalendarException(MSG_MISSING_PREFIX + String.join(missing, ', '));
        }
        Integer taken = VolunteerCalendarAccessHelper.countActiveAssignments(new Set<Id>{ shift.Id }).get(shift.Id) ?? 0;
        if (shift.MaximumAttendeesCount != null && taken >= shift.MaximumAttendeesCount) {
            throw new CalendarException(MSG_SHIFT_FULL);
        }
        VolunteerCalendarAccessHelper.createAssignment(
            new JobPositionAssignment(
                AssignedPositionShiftId = shift.Id,
                JobPositionId = shift.JobPositionId,
                RelatedVolunteerInitiativeId = shift.JobPosition.VolunteerInitiativeId,
                AssignedAccountId = identity.accountId,
                ScheduledStartTime = startAt,
                ScheduledEndTime = endAt,
                Status = STATUS_UPCOMING
            )
        );
        return buildDetail(shift, identity);
    }

    /**
     * Turns a shift's date, time, and time zone into one exact moment.
     * @param shiftDate The date on the shift.
     * @param shiftTime The time on the shift.
     * @param timeZoneName The shift's time zone ID. When blank, the company time zone is used.
     * @return The moment in time.
     */
    @TestVisible
    private static Datetime toInstant(Date shiftDate, Time shiftTime, String timeZoneName) {
        String zoneName = String.isBlank(timeZoneName) ? VolunteerCalendarAccessHelper.getCompanyTimeZoneName() : timeZoneName;
        TimeZone zone = TimeZone.getTimeZone(zoneName);
        Datetime wallClock = Datetime.newInstanceGmt(shiftDate, shiftTime);
        Datetime firstGuess = Datetime.newInstance(wallClock.getTime() - zone.getOffset(wallClock));
        return Datetime.newInstance(wallClock.getTime() - zone.getOffset(firstGuess));
    }

    private static JobPositionShift loadOpenShift(Id shiftId, Boolean lockRecord) {
        List<JobPositionShift> shifts = VolunteerCalendarAccessHelper.getOpenShift(shiftId, ACTIVE_SHIFT_STATUSES, lockRecord);
        if (shifts.isEmpty()) {
            throw new CalendarException(MSG_SHIFT_UNAVAILABLE);
        }
        return shifts[0];
    }

    private static VolunteerIdentity getIdentity() {
        if (testIdentity != null) {
            return testIdentity;
        }
        return VolunteerCalendarAccessHelper.getVolunteerIdentity(UserInfo.getUserId());
    }

    private static ShiftDetailDto buildDetail(JobPositionShift shift, VolunteerIdentity identity) {
        Map<Id, Integer> counts = VolunteerCalendarAccessHelper.countActiveAssignments(new Set<Id>{ shift.Id });
        ShiftDetailDto detail = new ShiftDetailDto();
        detail.shift = toShiftDto(shift, counts.get(shift.Id) ?? 0);
        detail.description = shift.Description;
        Datetime startAt = toInstant(shift.StartDate, shift.StartTime, shift.TimeZone);
        detail.qualifications = evaluateQualifications(shift.JobPositionId, identity, shift.StartDate, startAt);
        detail.alreadySignedUp = identity.accountId != null && VolunteerCalendarAccessHelper.hasActiveAssignment(shift.Id, identity.accountId);
        List<String> missing = missingNames(detail.qualifications);
        if (detail.alreadySignedUp) {
            detail.blockedMessage = null;
        } else if (identity.accountId == null) {
            detail.blockedMessage = MSG_NO_ACCOUNT;
        } else if (!missing.isEmpty()) {
            detail.blockedMessage = MSG_MISSING_PREFIX + String.join(missing, ', ');
        } else if (detail.shift.isFull) {
            detail.blockedMessage = MSG_SHIFT_FULL;
        }
        detail.canSignUp = !detail.alreadySignedUp && identity.accountId != null && missing.isEmpty() && !detail.shift.isFull;
        return detail;
    }

    private static ShiftDto toShiftDto(JobPositionShift shift, Integer assignedCount) {
        ShiftDto dto = new ShiftDto();
        dto.id = shift.Id;
        dto.positionId = shift.JobPositionId;
        dto.positionName = shift.JobPosition.Title;
        dto.initiativeId = shift.JobPosition.VolunteerInitiativeId;
        dto.initiativeName = shift.JobPosition.VolunteerInitiative?.Name;
        dto.color = resolveColor(shift.JobPositionId, shift.JobPosition.Calendar_Color__c);
        dto.startDateTime = toIso(toInstant(shift.StartDate, shift.StartTime, shift.TimeZone));
        dto.endDateTime = toIso(toInstant(shift.EndDate, shift.EndTime, shift.TimeZone));
        dto.maximumAttendees = shift.MaximumAttendeesCount;
        dto.isUnlimited = shift.MaximumAttendeesCount == null;
        dto.remainingCapacity = dto.isUnlimited ? null : Math.max(0, shift.MaximumAttendeesCount - assignedCount);
        dto.isFull = !dto.isUnlimited && dto.remainingCapacity == 0;
        return dto;
    }

    @TestVisible
    private static String resolveColor(Id positionId, String chosenColor) {
        if (String.isNotBlank(chosenColor)) {
            return chosenColor;
        }
        return COLOR_PALETTE[Math.mod(Math.abs(String.valueOf(positionId).hashCode()), COLOR_PALETTE.size())];
    }

    private static String toIso(Datetime value) {
        return value.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
    }

    private static List<OptionDto> toSortedOptions(Map<Id, String> labelsById) {
        List<OptionDto> options = new List<OptionDto>();
        for (Id recordId : labelsById.keySet()) {
            OptionDto option = new OptionDto();
            option.value = recordId;
            option.label = labelsById.get(recordId);
            options.add(option);
        }
        options.sort();
        return options;
    }

    private static List<String> missingNames(List<QualificationDto> qualifications) {
        List<String> missing = new List<String>();
        for (QualificationDto qualification : qualifications) {
            if (qualification.status != QUALIFICATION_MET) {
                missing.add(qualification.name);
            }
        }
        return missing;
    }

    /**
     * A qualification is met when the volunteer has a matching record that has started on or before the
     * shift start and has no end, or ends on or after the shift start. A record with no start is not met.
     */
    private static List<QualificationDto> evaluateQualifications(Id positionId, VolunteerIdentity identity, Date shiftDate, Datetime shiftStart) {
        List<JobPositionQualification> qualifications = VolunteerCalendarAccessHelper.getPositionQualifications(positionId);
        Set<Id> competencyIds = new Set<Id>();
        Set<Id> examinationIds = new Set<Id>();
        for (JobPositionQualification qualification : qualifications) {
            Id referenceId = qualification.QualificationReferenceRecordId;
            String objectName = referenceId == null ? '' : String.valueOf(referenceId.getSObjectType());
            if (objectName == TYPE_COMPETENCY) {
                competencyIds.add(referenceId);
            } else if (objectName == TYPE_EXAMINATION) {
                examinationIds.add(referenceId);
            }
        }
        Map<Id, String> names = VolunteerCalendarAccessHelper.getQualificationNames(competencyIds, examinationIds);
        Set<Id> accountIds = identity.accountId == null ? new Set<Id>() : new Set<Id>{ identity.accountId };
        Set<Id> contactIds = identity.contactId == null ? new Set<Id>() : new Set<Id>{ identity.contactId };
        List<PersonCompetency> personCompetencies = VolunteerCalendarAccessHelper.getPersonCompetencies(accountIds, contactIds, competencyIds);
        List<PersonExamination> personExaminations = VolunteerCalendarAccessHelper.getPersonExaminations(accountIds, contactIds, examinationIds);

        List<QualificationDto> results = new List<QualificationDto>();
        for (Id referenceId : competencyIds) {
            results.add(buildQualification(referenceId, TYPE_COMPETENCY, names, competencyStatus(referenceId, personCompetencies, shiftDate)));
        }
        for (Id referenceId : examinationIds) {
            results.add(buildQualification(referenceId, TYPE_EXAMINATION, names, examinationStatus(referenceId, personExaminations, shiftStart)));
        }
        results.sort(new QualificationNameComparator());
        return results;
    }

    private static QualificationDto buildQualification(Id referenceId, String typeName, Map<Id, String> names, String status) {
        QualificationDto dto = new QualificationDto();
        dto.referenceId = referenceId;
        dto.name = names.get(referenceId) ?? typeName;
        dto.qualificationType = typeName;
        dto.status = status;
        return dto;
    }

    private static String competencyStatus(Id competencyId, List<PersonCompetency> records, Date shiftDate) {
        Boolean expired = false;
        for (PersonCompetency record : records) {
            if (record.CompetencyId != competencyId || record.EffectiveStartDate == null || record.EffectiveStartDate > shiftDate) {
                continue;
            }
            if (record.EffectiveEndDate == null || record.EffectiveEndDate >= shiftDate) {
                return QUALIFICATION_MET;
            }
            expired = true;
        }
        return expired ? QUALIFICATION_EXPIRED : QUALIFICATION_NOT_MET;
    }

    private static String examinationStatus(Id examinationId, List<PersonExamination> records, Datetime shiftStart) {
        Boolean expired = false;
        for (PersonExamination record : records) {
            if (record.ExaminationId != examinationId || record.EffectiveFrom == null || record.EffectiveFrom > shiftStart) {
                continue;
            }
            if (record.EffectiveTo == null || record.EffectiveTo >= shiftStart) {
                return QUALIFICATION_MET;
            }
            expired = true;
        }
        return expired ? QUALIFICATION_EXPIRED : QUALIFICATION_NOT_MET;
    }

    private class QualificationNameComparator implements System.Comparator<QualificationDto> {
        public Integer compare(QualificationDto first, QualificationDto second) {
            return (first.name ?? '').compareTo(second.name ?? '');
        }
    }
}
