/** Builds the Volunteer Management records the volunteer calendar tests need. */
@IsTest
public class VolunteerCalendarTestDataFactory {
    public static final String SHIFT_TIME_ZONE = 'America/New_York';
    private static final String PERMISSION_SET_NAME = 'Volunteer_Calendar_Access';

    /** Creates the records shared by every test: a volunteer, an initiative, a competency, and an examination. */
    public static void createBaseData() {
        createVolunteer('Primary');
        insert as system new VolunteerInitiative(Name = 'Community Garden', Status = 'Upcoming');
        insert as system new Competency(Name = 'First Aid');
        insert as system new Examination(Name = 'Food Safety Exam');
    }

    /** Gives a user the same permission set volunteers get, so tests run with realistic field access. */
    public static void assignVolunteerPermissionSet(Id userId) {
        Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :PERMISSION_SET_NAME LIMIT 1].Id;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert as system new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = permissionSetId);
        }
    }

    public static Account createVolunteer(String lastName) {
        Id personRecordTypeId = [SELECT Id FROM RecordType WHERE SObjectType = 'Account' AND IsPersonType = true LIMIT 1].Id;
        Account volunteer = new Account(FirstName = 'Test', LastName = lastName, RecordTypeId = personRecordTypeId);
        insert as system volunteer;
        return volunteer;
    }

    public static JobPosition createPosition(String title, Id initiativeId, String color) {
        JobPosition position = new JobPosition(
            Name = title,
            Title = title,
            Status = 'Upcoming',
            VolunteerInitiativeId = initiativeId,
            Calendar_Color__c = color
        );
        insert as system position;
        return position;
    }

    public static JobPositionShift createShift(Id positionId, Integer daysFromToday, Integer maximumAttendees) {
        JobPositionShift shift = buildShift(positionId, daysFromToday, maximumAttendees);
        insert as system shift;
        return shift;
    }

    public static JobPositionShift buildShift(Id positionId, Integer daysFromToday, Integer maximumAttendees) {
        Date shiftDate = Date.today().addDays(daysFromToday);
        return new JobPositionShift(
            JobPositionId = positionId,
            Description = 'Help out at the garden',
            Published__c = true,
            Status = 'Upcoming',
            StartDate = shiftDate,
            StartTime = Time.newInstance(9, 0, 0, 0),
            EndDate = shiftDate,
            EndTime = Time.newInstance(13, 0, 0, 0),
            TimeZone = SHIFT_TIME_ZONE,
            MaximumAttendeesCount = maximumAttendees
        );
    }

    public static JobPositionQualification createQualification(Id positionId, Id referenceId) {
        JobPositionQualification qualification = new JobPositionQualification(
            JobPositionId = positionId,
            QualificationReferenceRecordId = referenceId
        );
        insert as system qualification;
        return qualification;
    }

    public static PersonCompetency createPersonCompetency(Id personId, Id competencyId, Date startDate, Date endDate) {
        PersonCompetency record = new PersonCompetency(
            PersonId = personId,
            CompetencyId = competencyId,
            ProficiencyLevel = 'Beginner',
            EffectiveStartDate = startDate,
            EffectiveEndDate = endDate
        );
        insert as system record;
        return record;
    }

    public static PersonExamination createPersonExamination(Id accountId, Id examinationId, Datetime effectiveFrom, Datetime effectiveTo) {
        PersonExamination record = new PersonExamination(
            AccountId = accountId,
            ExaminationId = examinationId,
            EffectiveFrom = effectiveFrom,
            EffectiveTo = effectiveTo
        );
        insert as system record;
        return record;
    }

    public static JobPositionAssignment createAssignment(JobPositionShift shift, Id accountId, String status) {
        JobPositionAssignment assignment = new JobPositionAssignment(
            AssignedPositionShiftId = shift.Id,
            JobPositionId = shift.JobPositionId,
            AssignedAccountId = accountId,
            Status = status
        );
        insert as system assignment;
        return assignment;
    }
}
