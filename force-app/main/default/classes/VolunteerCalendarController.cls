/**
 * Entry points the volunteer shift calendar component calls. Every method returns plain-language
 * errors only, so volunteers never see technical text.
 */
public with sharing class VolunteerCalendarController {
    private static final String MSG_GENERIC = 'Something went wrong on our side. Please try again in a moment.';

    /**
     * @return The Position and Volunteer Initiative filter choices.
     */
    @AuraEnabled(cacheable=true)
    public static VolunteerCalendarService.FilterOptionsDto getFilterOptions() {
        try {
            return VolunteerCalendarService.getFilterOptions();
        } catch (Exception caught) {
            throw friendlyError(caught);
        }
    }

    /**
     * @param rangeStart First day to include.
     * @param rangeEnd Last day to include.
     * @return The shifts in that range.
     */
    @AuraEnabled
    public static List<VolunteerCalendarService.ShiftDto> getShifts(Date rangeStart, Date rangeEnd) {
        try {
            return VolunteerCalendarService.getShifts(rangeStart, rangeEnd);
        } catch (Exception caught) {
            throw friendlyError(caught);
        }
    }

    /**
     * @param shiftId The shift to show.
     * @return The details and sign-up state for the pop-up.
     */
    @AuraEnabled
    public static VolunteerCalendarService.ShiftDetailDto getShiftDetail(Id shiftId) {
        try {
            return VolunteerCalendarService.getShiftDetail(shiftId);
        } catch (Exception caught) {
            throw friendlyError(caught);
        }
    }

    /**
     * @param shiftId The shift to sign up for.
     * @return The refreshed details, now in the signed-up state.
     */
    @AuraEnabled
    public static VolunteerCalendarService.ShiftDetailDto signUp(Id shiftId) {
        try {
            return VolunteerCalendarService.signUp(shiftId);
        } catch (Exception caught) {
            throw friendlyError(caught);
        }
    }

    private static AuraHandledException friendlyError(Exception caught) {
        String message = caught instanceof VolunteerCalendarService.CalendarException ? caught.getMessage() : MSG_GENERIC;
        AuraHandledException friendly = new AuraHandledException(message);
        friendly.setMessage(message);
        return friendly;
    }
}
