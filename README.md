# Volunteer Shift Calendar

A calendar for your Experience Cloud site. Logged-in volunteers can see published, upcoming shifts and sign up for them. It uses the Nonprofit Cloud Volunteer Management objects (Job Position Shift, Job Position, Volunteer Initiative, and Job Position Assignment).

## What is included

- **Volunteer Shift Calendar** component (`volunteerShiftCalendar`) that you place on a site page.
- **Published** checkbox on Job Position Shift. Only published shifts appear on the calendar.
- **Calendar Color** picklist on Job Position (Blue, Green, Orange, Purple, Teal). Positions with no color get one automatically.
- **Volunteer Calendar Access** permission set for volunteers, and **Volunteer Calendar Manager** permission set for staff.
- Apex classes that read shifts and check qualifications, capacity, and duplicate sign-ups on the server. Because of this, volunteers need no object or field permissions, so the calendar works with any site license.
- Read-only sharing rules for published shifts, open positions, and open initiatives. The calendar does not depend on them. They only matter if you also want volunteers to see this data somewhere else.

## Before you install

The org you install into needs these turned on, because the calendar is built on them:

- **Volunteer Management** (Nonprofit Cloud), which provides Job Position Shift, Job Position, Volunteer Initiative, and Job Position Assignment.
- **Person Accounts**, because each volunteer is a Person Account.
- **Digital Experiences** (Experience Cloud), so you can add the calendar to a site.

## Steps to finish after installing

1. **Give volunteers access.** In Setup, open **Permission Sets**, choose **Volunteer Calendar Access**, click **Manage Assignments**, and add your volunteer site users.
2. **Give your staff access.** In the same place, choose **Volunteer Calendar Manager** and add the Salesforce users who publish shifts and choose position colors. Without it, they cannot edit **Published** or **Calendar Color**.
3. **Add Published to the shift page layout.** In Setup, open **Object Manager**, then **Job Position Shift**, then **Page Layouts**. Edit the layout and drag the **Published** field onto it.
4. **Add Calendar Color to the position page layout.** In Setup, open **Object Manager**, then **Job Position**, then **Page Layouts**. Edit the layout and drag the **Calendar Color** field onto it.
5. **Add the calendar to your site.** Open **Experience Builder**, edit a page, and drag **Volunteer Shift Calendar** from the Components panel onto it. Use the settings panel to choose a title, which filters to show, and whether to show the color legend. Then publish your site.

## Good to know

- A shift only appears when **Published** is checked, it has a **Job Position**, its status is **Upcoming** or **In Progress**, and its start date is today or later. It also needs a start time, an end date, and an end time.
- Times show in each volunteer's own time zone. If a shift has no time zone, the company time zone is used.
- Leave **Maximum Attendees Count** blank for an unlimited shift.
- A volunteer must have a Person Account to sign up. Sign-ups are saved as **Upcoming** assignments.
- A qualification (Competency or Examination) is met when the volunteer has a matching record that started on or before the shift start and either has no end date or ends on or after the shift start. Otherwise it shows Not met, or Expired when it ended before the shift.
- Volunteers can only see published, active, upcoming shifts through the calendar, and only their own qualifications are checked. The calendar never shows another volunteer's information.

##Installation Links
- Production and Developer Edition orgs: https://login.salesforce.com/packaging/installPackage.apexp?p0=04tjV000000DvrhQAC
- Sandboxes: https://test.salesforce.com/packaging/installPackage.apexp?p0=04tjV000000DvrhQAC
