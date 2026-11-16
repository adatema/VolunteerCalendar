@IsTest
private class VolunteerCalendarTest {
    private static final Integer DAYS_OUT = 7;

    @TestSetup
    static void setupData() {
        VolunteerCalendarTestDataFactory.createBaseData();
        VolunteerCalendarTestDataFactory.assignVolunteerPermissionSet(UserInfo.getUserId());
    }

    // ---------- sign-up: qualified ----------

    @IsTest
    static void shouldCreateAssignment_WhenVolunteerIsQualified() {
        System.runAs(runningUser()) {
            Account volunteer = signInAsPrimaryVolunteer();
            VolunteerInitiative initiative = initiative();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Gardener', initiative.Id, 'Green');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 5);
            VolunteerCalendarTestDataFactory.createQualification(position.Id, competency().Id);
            VolunteerCalendarTestDataFactory.createPersonCompetency(volunteer.Id, competency().Id, Date.today().addDays(-30), null);

            Test.startTest();
            VolunteerCalendarService.ShiftDetailDto detail = VolunteerCalendarService.signUp(shift.Id);
            Test.stopTest();

            List<JobPositionAssignment> assignments = [
                SELECT AssignedAccountId, AssignedPositionShiftId, JobPositionId, RelatedVolunteerInitiativeId, Status, ScheduledStartTime, ScheduledEndTime
                FROM JobPositionAssignment
            ];
            Assert.areEqual(1, assignments.size(), 'One assignment should be created');
            Assert.areEqual(volunteer.Id, assignments[0].AssignedAccountId, 'Assignment should belong to the volunteer');
            Assert.areEqual(shift.Id, assignments[0].AssignedPositionShiftId, 'Assignment should point to the shift');
            Assert.areEqual(position.Id, assignments[0].JobPositionId, 'Assignment should copy the position');
            Assert.areEqual(initiative.Id, assignments[0].RelatedVolunteerInitiativeId, 'Assignment should copy the initiative');
            Assert.areEqual('Upcoming', assignments[0].Status, 'New assignments start as Upcoming');
            Assert.areEqual(expectedStart(shift), assignments[0].ScheduledStartTime, 'Scheduled start should match the shift start');
            Assert.areEqual(expectedEnd(shift), assignments[0].ScheduledEndTime, 'Scheduled end should match the shift end');
            Assert.isTrue(detail.alreadySignedUp, 'Detail should show the signed-up state');
            Assert.isFalse(detail.canSignUp, 'Sign-up should be disabled after signing up');
            Assert.areEqual(4, detail.shift.remainingCapacity, 'Remaining capacity should drop by one');
        }
    }

    @IsTest
    static void shouldCreateAssignment_WhenExaminationIsCurrent() {
        System.runAs(runningUser()) {
            Account volunteer = signInAsPrimaryVolunteer();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Cook', initiative().Id, 'Orange');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 5);
            VolunteerCalendarTestDataFactory.createQualification(position.Id, examination().Id);
            VolunteerCalendarTestDataFactory.createPersonExamination(volunteer.Id, examination().Id, Datetime.now().addDays(-20), Datetime.now().addDays(60));

            Test.startTest();
            VolunteerCalendarService.ShiftDetailDto detail = VolunteerCalendarService.signUp(shift.Id);
            Test.stopTest();

            Assert.isTrue(detail.alreadySignedUp, 'A current examination should qualify the volunteer');
            Assert.areEqual('Examination', detail.qualifications[0].qualificationType, 'Qualification should be an examination');
            Assert.areEqual('Met', detail.qualifications[0].status, 'Examination should be met');
        }
    }

    @IsTest
    static void shouldMatchQualification_WhenRecordUsesPersonContact() {
        System.runAs(runningUser()) {
            Account volunteer = signInAsPrimaryVolunteer();
            Id contactId = [SELECT PersonContactId FROM Account WHERE Id = :volunteer.Id].PersonContactId;
            VolunteerCalendarService.testIdentity.contactId = contactId;
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Greeter', initiative().Id, null);
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 5);
            VolunteerCalendarTestDataFactory.createQualification(position.Id, competency().Id);
            VolunteerCalendarTestDataFactory.createPersonCompetency(contactId, competency().Id, Date.today().addDays(-1), null);

            Test.startTest();
            VolunteerCalendarService.ShiftDetailDto detail = VolunteerCalendarService.getShiftDetail(shift.Id);
            Test.stopTest();

            Assert.isTrue(detail.canSignUp, 'A competency recorded on the person contact should count');
        }
    }

    @IsTest
    static void shouldAllowSignUp_WhenPositionHasNoQualifications() {
        System.runAs(runningUser()) {
            signInAsPrimaryVolunteer();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Helper', initiative().Id, 'Teal');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, null);

            Test.startTest();
            VolunteerCalendarService.ShiftDetailDto detail = VolunteerCalendarService.getShiftDetail(shift.Id);
            Test.stopTest();

            Assert.isTrue(detail.canSignUp, 'Anyone can sign up when there are no qualifications');
            Assert.isTrue(detail.qualifications.isEmpty(), 'There should be no qualifications');
            Assert.isTrue(detail.shift.isUnlimited, 'A blank maximum means unlimited');
            Assert.isNull(detail.shift.remainingCapacity, 'Unlimited shifts have no remaining number');
            Assert.isFalse(detail.shift.isFull, 'Unlimited shifts are never full');
        }
    }

    // ---------- sign-up: unqualified ----------

    @IsTest
    static void shouldRejectSignUp_WhenQualificationIsMissing() {
        System.runAs(runningUser()) {
            signInAsPrimaryVolunteer();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Nurse Aide', initiative().Id, 'Blue');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 5);
            VolunteerCalendarTestDataFactory.createQualification(position.Id, competency().Id);
            VolunteerCalendarTestDataFactory.createQualification(position.Id, examination().Id);

            Test.startTest();
            String message = signUpAndGetMessage(shift.Id);
            VolunteerCalendarService.ShiftDetailDto detail = VolunteerCalendarService.getShiftDetail(shift.Id);
            Test.stopTest();

            Assert.areEqual(VolunteerCalendarService.MSG_MISSING_PREFIX + 'First Aid, Food Safety Exam', message, 'Message should list every missing qualification');
            Assert.areEqual(VolunteerCalendarService.MSG_MISSING_PREFIX + 'First Aid, Food Safety Exam', detail.blockedMessage, 'Pop-up should show the same message');
            Assert.isFalse(detail.canSignUp, 'Sign-up should be disabled');
            Assert.areEqual(0, [SELECT COUNT() FROM JobPositionAssignment], 'No assignment should be created');
        }
    }

    @IsTest
    static void shouldTreatQualificationAsNotMet_WhenStartIsBlankOrInTheFuture() {
        System.runAs(runningUser()) {
            Account volunteer = signInAsPrimaryVolunteer();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Driver', initiative().Id, 'Purple');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 5);
            VolunteerCalendarTestDataFactory.createQualification(position.Id, competency().Id);
            VolunteerCalendarTestDataFactory.createQualification(position.Id, examination().Id);
            VolunteerCalendarTestDataFactory.createPersonCompetency(volunteer.Id, competency().Id, null, null);
            VolunteerCalendarTestDataFactory.createPersonExamination(volunteer.Id, examination().Id, Datetime.now().addDays(DAYS_OUT + 5), null);

            Test.startTest();
            VolunteerCalendarService.ShiftDetailDto detail = VolunteerCalendarService.getShiftDetail(shift.Id);
            Test.stopTest();

            for (VolunteerCalendarService.QualificationDto qualification : detail.qualifications) {
                Assert.areEqual('Not met', qualification.status, qualification.name + ' should be Not met without a valid start');
            }
            Assert.isFalse(detail.canSignUp, 'Sign-up should be disabled');
        }
    }

    @IsTest
    static void shouldTreatQualificationAsMet_WhenStartIsTheShiftDate() {
        System.runAs(runningUser()) {
            Account volunteer = signInAsPrimaryVolunteer();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Usher', initiative().Id, 'Blue');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 5);
            VolunteerCalendarTestDataFactory.createQualification(position.Id, competency().Id);
            VolunteerCalendarTestDataFactory.createPersonCompetency(volunteer.Id, competency().Id, shift.StartDate, shift.StartDate.addDays(30));

            Test.startTest();
            VolunteerCalendarService.ShiftDetailDto detail = VolunteerCalendarService.getShiftDetail(shift.Id);
            Test.stopTest();

            Assert.areEqual('Met', detail.qualifications[0].status, 'A start on the shift date counts as met');
        }
    }

    // ---------- sign-up: expired ----------

    @IsTest
    static void shouldRejectSignUp_WhenCompetencyExpiredBeforeShift() {
        System.runAs(runningUser()) {
            Account volunteer = signInAsPrimaryVolunteer();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Trainer', initiative().Id, 'Green');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 5);
            VolunteerCalendarTestDataFactory.createQualification(position.Id, competency().Id);
            VolunteerCalendarTestDataFactory.createPersonCompetency(volunteer.Id, competency().Id, Date.today().addDays(-90), Date.today().addDays(DAYS_OUT - 2));

            Test.startTest();
            VolunteerCalendarService.ShiftDetailDto detail = VolunteerCalendarService.getShiftDetail(shift.Id);
            String message = signUpAndGetMessage(shift.Id);
            Test.stopTest();

            Assert.areEqual('Expired', detail.qualifications[0].status, 'A competency that ends before the shift is Expired');
            Assert.isTrue(message.startsWith(VolunteerCalendarService.MSG_MISSING_PREFIX), 'Expired qualifications block sign-up');
            Assert.areEqual(0, [SELECT COUNT() FROM JobPositionAssignment], 'No assignment should be created');
        }
    }

    @IsTest
    static void shouldRejectSignUp_WhenExaminationExpiredBeforeShift() {
        System.runAs(runningUser()) {
            Account volunteer = signInAsPrimaryVolunteer();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Server', initiative().Id, 'Orange');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 5);
            VolunteerCalendarTestDataFactory.createQualification(position.Id, examination().Id);
            VolunteerCalendarTestDataFactory.createPersonExamination(volunteer.Id, examination().Id, Datetime.now().addDays(-120), Datetime.now().addDays(1));

            Test.startTest();
            VolunteerCalendarService.ShiftDetailDto detail = VolunteerCalendarService.getShiftDetail(shift.Id);
            Test.stopTest();

            Assert.areEqual('Expired', detail.qualifications[0].status, 'An examination that ends before the shift is Expired');
            Assert.isFalse(detail.canSignUp, 'Sign-up should be disabled');
        }
    }

    @IsTest
    static void shouldAcceptQualification_WhenOneOfSeveralRecordsIsValid() {
        System.runAs(runningUser()) {
            Account volunteer = signInAsPrimaryVolunteer();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Mentor', initiative().Id, 'Teal');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 5);
            VolunteerCalendarTestDataFactory.createQualification(position.Id, competency().Id);
            VolunteerCalendarTestDataFactory.createPersonCompetency(volunteer.Id, competency().Id, Date.today().addDays(-400), Date.today().addDays(-300));
            VolunteerCalendarTestDataFactory.createPersonCompetency(volunteer.Id, competency().Id, Date.today().addDays(-10), null);

            Test.startTest();
            VolunteerCalendarService.ShiftDetailDto detail = VolunteerCalendarService.getShiftDetail(shift.Id);
            Test.stopTest();

            Assert.areEqual('Met', detail.qualifications[0].status, 'A renewed record should win over an expired one');
        }
    }

    // ---------- sign-up: full, duplicate, unpublished ----------

    @IsTest
    static void shouldRejectSignUp_WhenShiftIsFull() {
        System.runAs(runningUser()) {
            signInAsPrimaryVolunteer();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Packer', initiative().Id, 'Blue');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 1);
            VolunteerCalendarTestDataFactory.createAssignment(shift, VolunteerCalendarTestDataFactory.createVolunteer('Other').Id, 'Upcoming');

            Test.startTest();
            String message = signUpAndGetMessage(shift.Id);
            List<VolunteerCalendarService.ShiftDto> shifts = VolunteerCalendarService.getShifts(Date.today(), Date.today().addDays(30));
            VolunteerCalendarService.ShiftDetailDto detail = VolunteerCalendarService.getShiftDetail(shift.Id);
            Test.stopTest();

            Assert.areEqual(VolunteerCalendarService.MSG_SHIFT_FULL, message, 'A full shift should say so');
            Assert.isTrue(shifts[0].isFull, 'The calendar should flag the shift as full');
            Assert.areEqual(0, shifts[0].remainingCapacity, 'Nothing should remain');
            Assert.isFalse(detail.canSignUp, 'Sign-up should be disabled on a full shift');
            Assert.areEqual(VolunteerCalendarService.MSG_SHIFT_FULL, detail.blockedMessage, 'Pop-up should explain why');
        }
    }

    @IsTest
    static void shouldNotCountCanceledAssignments_WhenCalculatingCapacity() {
        System.runAs(runningUser()) {
            signInAsPrimaryVolunteer();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Sorter', initiative().Id, 'Green');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 1);
            VolunteerCalendarTestDataFactory.createAssignment(shift, VolunteerCalendarTestDataFactory.createVolunteer('Dropped').Id, 'Canceled');

            Test.startTest();
            VolunteerCalendarService.ShiftDetailDto detail = VolunteerCalendarService.signUp(shift.Id);
            Test.stopTest();

            Assert.isTrue(detail.alreadySignedUp, 'The canceled spot should be available again');
            Assert.areEqual(0, detail.shift.remainingCapacity, 'The shift is now full');
        }
    }

    @IsTest
    static void shouldRejectSignUp_WhenVolunteerAlreadySignedUp() {
        System.runAs(runningUser()) {
            Account volunteer = signInAsPrimaryVolunteer();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Painter', initiative().Id, 'Purple');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 5);
            VolunteerCalendarTestDataFactory.createAssignment(shift, volunteer.Id, 'Upcoming');

            Test.startTest();
            String message = signUpAndGetMessage(shift.Id);
            VolunteerCalendarService.ShiftDetailDto detail = VolunteerCalendarService.getShiftDetail(shift.Id);
            Test.stopTest();

            Assert.areEqual(VolunteerCalendarService.MSG_ALREADY_SIGNED_UP, message, 'Duplicate sign-ups are blocked');
            Assert.isTrue(detail.alreadySignedUp, 'Pop-up should show the signed-up state');
            Assert.isFalse(detail.canSignUp, 'Sign-up should stay disabled');
            Assert.isNull(detail.blockedMessage, 'No blocking message is needed once signed up');
            Assert.areEqual(1, [SELECT COUNT() FROM JobPositionAssignment], 'No second assignment should be created');
        }
    }

    @IsTest
    static void shouldAllowSignUp_WhenEarlierAssignmentWasCanceled() {
        System.runAs(runningUser()) {
            Account volunteer = signInAsPrimaryVolunteer();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Planter', initiative().Id, 'Blue');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 5);
            VolunteerCalendarTestDataFactory.createAssignment(shift, volunteer.Id, 'Canceled');

            Test.startTest();
            VolunteerCalendarService.ShiftDetailDto detail = VolunteerCalendarService.signUp(shift.Id);
            Test.stopTest();

            Assert.isTrue(detail.alreadySignedUp, 'A canceled assignment should not block a new sign-up');
        }
    }

    @IsTest
    static void shouldHideAndRejectShift_WhenShiftIsNotPublished() {
        System.runAs(runningUser()) {
            signInAsPrimaryVolunteer();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Weeder', initiative().Id, 'Green');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.buildShift(position.Id, DAYS_OUT, 5);
            shift.Published__c = false;
            insert as system shift;

            Test.startTest();
            List<VolunteerCalendarService.ShiftDto> shifts = VolunteerCalendarService.getShifts(Date.today(), Date.today().addDays(30));
            String message = signUpAndGetMessage(shift.Id);
            Test.stopTest();

            Assert.isTrue(shifts.isEmpty(), 'Unpublished shifts must not appear');
            Assert.areEqual(VolunteerCalendarService.MSG_SHIFT_UNAVAILABLE, message, 'Sign-up must be refused on the server');
            Assert.areEqual(0, [SELECT COUNT() FROM JobPositionAssignment], 'No assignment should be created');
        }
    }

    @IsTest
    static void shouldRejectSignUp_WhenVolunteerHasNoAccount() {
        System.runAs(runningUser()) {
            VolunteerCalendarService.testIdentity = new VolunteerCalendarService.VolunteerIdentity();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Host', initiative().Id, 'Teal');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 5);

            Test.startTest();
            String message = signUpAndGetMessage(shift.Id);
            VolunteerCalendarService.ShiftDetailDto detail = VolunteerCalendarService.getShiftDetail(shift.Id);
            Test.stopTest();

            Assert.areEqual(VolunteerCalendarService.MSG_NO_ACCOUNT, message, 'Sign-up needs a volunteer account');
            Assert.areEqual(VolunteerCalendarService.MSG_NO_ACCOUNT, detail.blockedMessage, 'Pop-up should explain why');
            Assert.isFalse(detail.canSignUp, 'Sign-up should be disabled');
        }
    }

    @IsTest
    static void shouldFindNoVolunteerAccount_WhenRunningAsAnInternalUser() {
        System.runAs(runningUser()) {
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Scout', initiative().Id, 'Teal');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 5);

            Test.startTest();
            VolunteerCalendarService.ShiftDetailDto detail = VolunteerCalendarService.getShiftDetail(shift.Id);
            Test.stopTest();

            Assert.isFalse(detail.canSignUp, 'Internal users have no volunteer account');
        }
    }

    // ---------- which shifts appear ----------

    @IsTest
    static void shouldOnlyListPublishedActiveUpcomingShifts() {
        System.runAs(runningUser()) {
            signInAsPrimaryVolunteer();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Host', initiative().Id, 'Blue');
            JobPositionShift visible = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 5);
            JobPositionShift today = VolunteerCalendarTestDataFactory.buildShift(position.Id, 0, 5);
            today.Status = 'In Progress';
            JobPositionShift past = VolunteerCalendarTestDataFactory.buildShift(position.Id, -3, 5);
            JobPositionShift complete = VolunteerCalendarTestDataFactory.buildShift(position.Id, 2, 5);
            complete.Status = 'Complete';
            JobPositionShift canceled = VolunteerCalendarTestDataFactory.buildShift(position.Id, 3, 5);
            canceled.Status = 'Canceled';
            JobPositionShift noTimes = VolunteerCalendarTestDataFactory.buildShift(position.Id, 4, 5);
            noTimes.StartTime = null;
            insert as system new List<JobPositionShift>{ today, past, complete, canceled, noTimes };

            Test.startTest();
            List<VolunteerCalendarService.ShiftDto> shifts = VolunteerCalendarService.getShifts(Date.today().addDays(-10), Date.today().addDays(30));
            Test.stopTest();

            Set<Id> shownIds = new Set<Id>();
            for (VolunteerCalendarService.ShiftDto shown : shifts) {
                shownIds.add(shown.id);
            }
            Assert.areEqual(new Set<Id>{ visible.Id, today.Id }, shownIds, 'Only published, active shifts from today onward should appear');
        }
    }

    @IsTest
    static void shouldBuildFilterOptions_FromUpcomingPublishedShifts() {
        System.runAs(runningUser()) {
            signInAsPrimaryVolunteer();
            JobPosition cook = VolunteerCalendarTestDataFactory.createPosition('Cook', initiative().Id, 'Orange');
            JobPosition driver = VolunteerCalendarTestDataFactory.createPosition('Driver', null, 'Blue');
            VolunteerCalendarTestDataFactory.createShift(cook.Id, DAYS_OUT, 5);
            VolunteerCalendarTestDataFactory.createShift(cook.Id, DAYS_OUT + 1, 5);
            VolunteerCalendarTestDataFactory.createShift(driver.Id, DAYS_OUT, 5);
            VolunteerCalendarTestDataFactory.createPosition('Idle', null, 'Teal');

            Test.startTest();
            VolunteerCalendarService.FilterOptionsDto options = VolunteerCalendarService.getFilterOptions();
            Test.stopTest();

            Assert.areEqual(2, options.positions.size(), 'Only positions with upcoming published shifts are listed');
            Assert.areEqual('Cook', options.positions[0].label, 'Positions are sorted by name');
            Assert.areEqual('Driver', options.positions[1].label, 'Positions are sorted by name');
            Assert.areEqual(1, options.initiatives.size(), 'Only initiatives with upcoming published shifts are listed');
            Assert.areEqual('Community Garden', options.initiatives[0].label, 'The initiative name should be shown');
        }
    }

    @IsTest
    static void shouldRejectBadDateRanges() {
        System.runAs(runningUser()) {
            Test.startTest();
            for (List<Date> range : new List<List<Date>>{
                new List<Date>{ null, Date.today() },
                new List<Date>{ Date.today(), Date.today().addDays(-1) },
                new List<Date>{ Date.today(), Date.today().addDays(400) }
            }) {
                try {
                    VolunteerCalendarService.getShifts(range[0], range[1]);
                    Assert.fail('Expected a friendly date error');
                } catch (VolunteerCalendarService.CalendarException caught) {
                    Assert.areEqual(VolunteerCalendarService.MSG_BAD_DATES, caught.getMessage(), 'Bad ranges should give a plain message');
                }
            }
            Test.stopTest();
        }
    }

    // ---------- colors and time zones ----------

    @IsTest
    static void shouldUseChosenColor_AndStableAutomaticColorOtherwise() {
        System.runAs(runningUser()) {
            signInAsPrimaryVolunteer();
            JobPosition chosen = VolunteerCalendarTestDataFactory.createPosition('Chosen', initiative().Id, 'Purple');
            JobPosition automatic = VolunteerCalendarTestDataFactory.createPosition('Automatic', initiative().Id, null);
            VolunteerCalendarTestDataFactory.createShift(chosen.Id, DAYS_OUT, 5);
            VolunteerCalendarTestDataFactory.createShift(automatic.Id, DAYS_OUT, 5);
            VolunteerCalendarTestDataFactory.createShift(automatic.Id, DAYS_OUT + 1, 5);

            Test.startTest();
            List<VolunteerCalendarService.ShiftDto> first = VolunteerCalendarService.getShifts(Date.today(), Date.today().addDays(30));
            List<VolunteerCalendarService.ShiftDto> second = VolunteerCalendarService.getShifts(Date.today(), Date.today().addDays(30));
            Test.stopTest();

            Set<String> automaticColors = new Set<String>();
            for (Integer index = 0; index < first.size(); index++) {
                Assert.areEqual(first[index].color, second[index].color, 'Colors must not change between loads');
                Assert.isTrue(new Set<String>{ 'Blue', 'Green', 'Orange', 'Purple', 'Teal' }.contains(first[index].color), 'Colors come from the approved palette');
                if (first[index].positionId == automatic.Id) {
                    automaticColors.add(first[index].color);
                } else {
                    Assert.areEqual('Purple', first[index].color, 'A chosen color is used as-is');
                }
            }
            Assert.areEqual(1, automaticColors.size(), 'All shifts for one position share one color');
        }
    }

    @IsTest
    static void shouldConvertShiftTimesUsingTheShiftTimeZone() {
        System.runAs(runningUser()) {
            Test.startTest();
            Datetime winter = VolunteerCalendarService.toInstant(Date.newInstance(2027, 1, 15), Time.newInstance(9, 0, 0, 0), 'America/New_York');
            Datetime summer = VolunteerCalendarService.toInstant(Date.newInstance(2027, 7, 15), Time.newInstance(9, 0, 0, 0), 'America/New_York');
            Test.stopTest();

            Assert.areEqual(Datetime.newInstanceGmt(2027, 1, 15, 14, 0, 0), winter, '9 AM Eastern is 14:00 GMT in winter');
            Assert.areEqual(Datetime.newInstanceGmt(2027, 7, 15, 13, 0, 0), summer, '9 AM Eastern is 13:00 GMT in summer');
        }
    }

    @IsTest
    static void shouldUseCompanyTimeZone_WhenShiftTimeZoneIsBlank() {
        System.runAs(runningUser()) {
            Date shiftDate = Date.newInstance(2027, 1, 15);
            Time shiftTime = Time.newInstance(9, 0, 0, 0);
            TimeZone company = TimeZone.getTimeZone(VolunteerCalendarAccessHelper.getCompanyTimeZoneName());
            Datetime wallClock = Datetime.newInstanceGmt(shiftDate, shiftTime);
            Datetime expected = Datetime.newInstance(wallClock.getTime() - company.getOffset(wallClock));

            Test.startTest();
            Datetime actual = VolunteerCalendarService.toInstant(shiftDate, shiftTime, null);
            Test.stopTest();

            Assert.areEqual(expected, actual, 'A blank time zone should fall back to the company time zone');
        }
    }

    // ---------- validation rule ----------

    @IsTest
    static void shouldBlockSaving_WhenPublishedShiftHasNoPosition() {
        System.runAs(runningUser()) {
            JobPositionShift shift = new JobPositionShift(Published__c = true, Status = 'Upcoming');

            Test.startTest();
            Database.SaveResult result = Database.insert(shift, false, AccessLevel.SYSTEM_MODE);
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'A published shift with no position must not save');
            Assert.areEqual(0, [SELECT COUNT() FROM JobPositionShift], 'Nothing should be saved');
        }
    }

    @IsTest
    static void shouldSaveShift_WhenPublishedShiftHasPosition() {
        System.runAs(runningUser()) {
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Greeter', initiative().Id, 'Blue');

            Test.startTest();
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 5);
            Test.stopTest();

            Assert.isNotNull(shift.Id, 'A published shift with a position should save');
        }
    }

    // ---------- controller ----------

    @IsTest
    static void shouldReturnData_ThroughController() {
        System.runAs(runningUser()) {
            Account volunteer = signInAsPrimaryVolunteer();
            JobPosition position = VolunteerCalendarTestDataFactory.createPosition('Gardener', initiative().Id, 'Green');
            JobPositionShift shift = VolunteerCalendarTestDataFactory.createShift(position.Id, DAYS_OUT, 5);

            Test.startTest();
            VolunteerCalendarService.FilterOptionsDto options = VolunteerCalendarController.getFilterOptions();
            List<VolunteerCalendarService.ShiftDto> shifts = VolunteerCalendarController.getShifts(Date.today(), Date.today().addDays(30));
            VolunteerCalendarService.ShiftDetailDto before = VolunteerCalendarController.getShiftDetail(shift.Id);
            VolunteerCalendarService.ShiftDetailDto after = VolunteerCalendarController.signUp(shift.Id);
            Test.stopTest();

            Assert.areEqual(1, options.positions.size(), 'Filter options should come back');
            Assert.areEqual(1, shifts.size(), 'Shifts should come back');
            Assert.isTrue(before.canSignUp, 'Volunteer can sign up before');
            Assert.isTrue(after.alreadySignedUp, 'Volunteer is signed up after');
            Assert.areEqual(volunteer.Id, [SELECT AssignedAccountId FROM JobPositionAssignment].AssignedAccountId, 'Assignment belongs to the volunteer');
        }
    }

    @IsTest
    static void shouldShowFriendlyMessages_WhenControllerCallsFail() {
        System.runAs(runningUser()) {
            signInAsPrimaryVolunteer();
            Test.startTest();
            try {
                VolunteerCalendarController.getShifts(null, null);
                Assert.fail('Expected a friendly error');
            } catch (AuraHandledException caught) {
                Assert.areEqual(VolunteerCalendarService.MSG_BAD_DATES, caught.getMessage(), 'Message should be plain language');
            }
            try {
                VolunteerCalendarController.signUp(null);
                Assert.fail('Expected a friendly error');
            } catch (AuraHandledException caught) {
                Assert.areEqual(VolunteerCalendarService.MSG_SHIFT_UNAVAILABLE, caught.getMessage(), 'Message should be plain language');
            }
            try {
                VolunteerCalendarController.getShiftDetail(null);
                Assert.fail('Expected a friendly error');
            } catch (AuraHandledException caught) {
                Assert.areEqual(VolunteerCalendarService.MSG_SHIFT_UNAVAILABLE, caught.getMessage(), 'Message should be plain language');
            }
            Test.stopTest();
        }
    }

    // ---------- helpers ----------

    private static User runningUser() {
        return new User(Id = UserInfo.getUserId());
    }

    private static Account signInAsPrimaryVolunteer() {
        Account volunteer = [SELECT Id FROM Account WHERE LastName = 'Primary' LIMIT 1];
        VolunteerCalendarService.VolunteerIdentity identity = new VolunteerCalendarService.VolunteerIdentity();
        identity.accountId = volunteer.Id;
        VolunteerCalendarService.testIdentity = identity;
        return volunteer;
    }

    private static VolunteerInitiative initiative() {
        return [SELECT Id FROM VolunteerInitiative LIMIT 1];
    }

    private static Competency competency() {
        return [SELECT Id FROM Competency LIMIT 1];
    }

    private static Examination examination() {
        return [SELECT Id FROM Examination LIMIT 1];
    }

    private static String signUpAndGetMessage(Id shiftId) {
        try {
            VolunteerCalendarService.signUp(shiftId);
        } catch (VolunteerCalendarService.CalendarException caught) {
            return caught.getMessage();
        }
        Assert.fail('Expected sign-up to be refused');
        return null;
    }

    private static Datetime expectedStart(JobPositionShift shift) {
        return VolunteerCalendarService.toInstant(shift.StartDate, shift.StartTime, shift.TimeZone);
    }

    private static Datetime expectedEnd(JobPositionShift shift) {
        return VolunteerCalendarService.toInstant(shift.EndDate, shift.EndTime, shift.TimeZone);
    }
}
