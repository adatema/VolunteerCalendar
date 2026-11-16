import { LightningElement, api } from 'lwc';
import getShifts from '@salesforce/apex/VolunteerCalendarController.getShifts';
import getFilterOptions from '@salesforce/apex/VolunteerCalendarController.getFilterOptions';
import getShiftDetail from '@salesforce/apex/VolunteerCalendarController.getShiftDetail';
import signUp from '@salesforce/apex/VolunteerCalendarController.signUp';

const MAX_VISIBLE_SHIFTS = 3;
const ANY_LENGTH_HOURS = 12;
const MINUTES_PER_DAY = 1440;
const KNOWN_COLORS = ['Blue', 'Green', 'Orange', 'Purple', 'Teal'];

const MSG_LOAD_FAILED = 'We could not load the shifts right now. Please try again in a moment.';
const MSG_DETAIL_FAILED = 'We could not load the details for this shift. Please close this window and try again.';
const MSG_SIGN_UP_FAILED = 'We could not sign you up right now. Please try again in a moment.';
const MSG_SIGNED_UP = 'Thank you! You are now signed up for this shift.';
const MSG_NO_MATCH = 'No shifts match your filters.';
const MSG_NO_SHIFTS = 'There are no shifts open for sign-up this month.';

const TIME_FORMAT = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' });
const FULL_FORMAT = new Intl.DateTimeFormat(undefined, {
    year: 'numeric',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
    timeZoneName: 'short'
});
const MONTH_FORMAT = new Intl.DateTimeFormat(undefined, { month: 'long', year: 'numeric' });
const LONG_DAY_FORMAT = new Intl.DateTimeFormat(undefined, { weekday: 'long', month: 'long', day: 'numeric' });
const WEEKDAY_FORMAT = new Intl.DateTimeFormat(undefined, { weekday: 'short' });

const pad = (value) => String(value).padStart(2, '0');
const toDateKey = (date) => `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
const toMinutes = (timeText) => {
    const [hours, minutes] = timeText.split(':').map(Number);
    return hours * 60 + minutes;
};

const readError = (error, fallback) => {
    const message = error && error.body && error.body.message;
    return typeof message === 'string' && message ? message : fallback;
};

const enrichShift = (raw) => {
    const start = new Date(raw.startDateTime);
    const end = new Date(raw.endDateTime);
    const startKey = toDateKey(start);
    const endKey = toDateKey(end);
    const color = KNOWN_COLORS.includes(raw.color) ? raw.color : KNOWN_COLORS[0];
    let capacityLabel = 'Spots left: Unlimited';
    if (raw.isFull) {
        capacityLabel = 'Full';
    } else if (!raw.isUnlimited) {
        capacityLabel = `Spots left: ${raw.remainingCapacity}`;
    }
    const timeLabel = `${TIME_FORMAT.format(start)} - ${TIME_FORMAT.format(end)}`;
    const names = [raw.positionName, raw.initiativeName].filter(Boolean).join(', ');
    return {
        id: raw.id,
        positionId: raw.positionId,
        positionName: raw.positionName,
        initiativeId: raw.initiativeId,
        initiativeName: raw.initiativeName,
        color,
        isFull: raw.isFull === true,
        capacityLabel,
        timeLabel,
        startMs: start.getTime(),
        dateKey: startKey,
        startMinutes: start.getHours() * 60 + start.getMinutes(),
        endMinutes: end.getHours() * 60 + end.getMinutes() + (endKey > startKey ? MINUTES_PER_DAY : 0),
        durationHours: (end.getTime() - start.getTime()) / 3600000,
        ariaLabel: raw.isFull
            ? `${names}, ${timeLabel}. This shift is full and cannot be selected.`
            : `${names}, ${timeLabel}. ${capacityLabel}. Select to see details.`,
        buttonClass: `shift color-${color}${raw.isFull ? ' shift--full' : ''}`,
        focusKey: `shift:${raw.id}`
    };
};

export default class VolunteerShiftCalendar extends LightningElement {
    @api calendarTitle;
    @api showPositionFilter;
    @api showInitiativeFilter;
    @api showDateRangeFilter;
    @api showStartTimeFilter;
    @api showEndTimeFilter;
    @api showShiftLengthFilter;
    @api showColorLegend;

    viewYear;
    viewMonth;
    shifts = [];
    days = [];
    legend = [];
    isLoading = true;
    loadError;

    positionOptions = [];
    initiativeOptions = [];
    positionId = '';
    initiativeId = '';
    fromDate = '';
    toDate = '';
    startTime = '';
    endTime = '';
    maxHours = ANY_LENGTH_HOURS;

    dialogType;
    dayKey;
    detail;
    detailLoading = false;
    detailError;
    successMessage;
    signUpError;
    signingUp = false;
    selectedShiftId;

    _loadRequestId = 0;
    _detailRequestId = 0;
    _focusDialog = false;
    _pendingFocusKey;
    _returnFocusKey;

    connectedCallback() {
        const today = new Date();
        this.viewYear = today.getFullYear();
        this.viewMonth = today.getMonth();
        this.rebuild();
        this.loadFilterOptions();
        this.loadShifts();
    }

    renderedCallback() {
        if (this._focusDialog) {
            const dialog = this.template.querySelector('.dialog');
            if (dialog) {
                dialog.focus();
                this._focusDialog = false;
            }
        }
        if (this._pendingFocusKey && !this.dialogType) {
            const target = this.template.querySelector(`[data-focus-key="${this._pendingFocusKey}"]`);
            if (target) {
                target.focus();
            }
            this._pendingFocusKey = undefined;
        }
    }

    // ---------- settings (Experience Builder) ----------

    get isPositionFilterOn() {
        return this.showPositionFilter !== false;
    }
    get isInitiativeFilterOn() {
        return this.showInitiativeFilter !== false;
    }
    get isDateRangeFilterOn() {
        return this.showDateRangeFilter !== false;
    }
    get isStartTimeFilterOn() {
        return this.showStartTimeFilter !== false;
    }
    get isEndTimeFilterOn() {
        return this.showEndTimeFilter !== false;
    }
    get isShiftLengthFilterOn() {
        return this.showShiftLengthFilter !== false;
    }
    get showFilterBar() {
        return (
            this.isPositionFilterOn ||
            this.isInitiativeFilterOn ||
            this.isDateRangeFilterOn ||
            this.isStartTimeFilterOn ||
            this.isEndTimeFilterOn ||
            this.isShiftLengthFilterOn
        );
    }
    get showLegend() {
        return this.showColorLegend !== false && this.legend.length > 0;
    }

    // ---------- filter bar ----------

    get positionChoices() {
        return this.positionOptions.map((option) => ({ ...option, selected: option.value === this.positionId }));
    }
    get initiativeChoices() {
        return this.initiativeOptions.map((option) => ({ ...option, selected: option.value === this.initiativeId }));
    }
    get noPositionSelected() {
        return !this.positionId;
    }
    get noInitiativeSelected() {
        return !this.initiativeId;
    }
    get shiftLengthText() {
        if (this.maxHours >= ANY_LENGTH_HOURS) {
            return 'Any length';
        }
        return `Less than ${this.maxHours} ${this.maxHours === 1 ? 'hour' : 'hours'}`;
    }
    get hasActiveFilters() {
        return (
            (this.isPositionFilterOn && !!this.positionId) ||
            (this.isInitiativeFilterOn && !!this.initiativeId) ||
            (this.isDateRangeFilterOn && (!!this.fromDate || !!this.toDate)) ||
            (this.isStartTimeFilterOn && !!this.startTime) ||
            (this.isEndTimeFilterOn && !!this.endTime) ||
            (this.isShiftLengthFilterOn && this.maxHours < ANY_LENGTH_HOURS)
        );
    }

    handleFilterChange(event) {
        const name = event.target.dataset.filter;
        const value = event.target.value;
        if (name === 'maxHours') {
            this.maxHours = Number(value);
        } else {
            this[name] = value;
        }
        if (name === 'fromDate' && value) {
            const [year, month] = value.split('-').map(Number);
            if (year && month && (year !== this.viewYear || month - 1 !== this.viewMonth)) {
                this.viewYear = year;
                this.viewMonth = month - 1;
                this.rebuild();
                this.loadShifts();
                return;
            }
        }
        this.rebuild();
    }

    handleClearFilters() {
        this.positionId = '';
        this.initiativeId = '';
        this.fromDate = '';
        this.toDate = '';
        this.startTime = '';
        this.endTime = '';
        this.maxHours = ANY_LENGTH_HOURS;
        this.rebuild();
    }

    applyFilters(list) {
        const startFloor = this.startTime ? toMinutes(this.startTime) : null;
        const endCeiling = this.endTime ? toMinutes(this.endTime) : null;
        return list.filter((shift) => {
            if (this.isPositionFilterOn && this.positionId && shift.positionId !== this.positionId) {
                return false;
            }
            if (this.isInitiativeFilterOn && this.initiativeId && shift.initiativeId !== this.initiativeId) {
                return false;
            }
            if (this.isDateRangeFilterOn) {
                if (this.fromDate && shift.dateKey < this.fromDate) {
                    return false;
                }
                if (this.toDate && shift.dateKey > this.toDate) {
                    return false;
                }
            }
            if (this.isStartTimeFilterOn && startFloor !== null && shift.startMinutes < startFloor) {
                return false;
            }
            if (this.isEndTimeFilterOn && endCeiling !== null && shift.endMinutes > endCeiling) {
                return false;
            }
            if (this.isShiftLengthFilterOn && this.maxHours < ANY_LENGTH_HOURS && shift.durationHours > this.maxHours) {
                return false;
            }
            return true;
        });
    }

    // ---------- calendar ----------

    get monthLabel() {
        return MONTH_FORMAT.format(new Date(this.viewYear, this.viewMonth, 1));
    }
    get gridLabel() {
        return `Shifts for ${this.monthLabel}`;
    }
    get weekdayLabels() {
        return [0, 1, 2, 3, 4, 5, 6].map((index) => ({
            key: `weekday-${index}`,
            label: WEEKDAY_FORMAT.format(new Date(2023, 0, 1 + index))
        }));
    }
    get hasVisibleShifts() {
        return this.days.some((day) => day.isInMonth && day.hasShifts);
    }
    get showEmptyMessage() {
        return !this.isLoading && !this.loadError && !this.hasVisibleShifts;
    }
    get emptyMessage() {
        return this.hasActiveFilters ? MSG_NO_MATCH : MSG_NO_SHIFTS;
    }

    gridRange() {
        const first = new Date(this.viewYear, this.viewMonth, 1);
        const daysInMonth = new Date(this.viewYear, this.viewMonth + 1, 0).getDate();
        const weeks = Math.ceil((first.getDay() + daysInMonth) / 7);
        const gridStart = new Date(this.viewYear, this.viewMonth, 1 - first.getDay());
        return { gridStart, weeks };
    }

    rebuild() {
        const { gridStart, weeks } = this.gridRange();
        const visible = this.applyFilters(this.shifts);
        const byDay = new Map();
        visible
            .slice()
            .sort((a, b) => a.startMs - b.startMs)
            .forEach((shift) => {
                if (!byDay.has(shift.dateKey)) {
                    byDay.set(shift.dateKey, []);
                }
                byDay.get(shift.dateKey).push(shift);
            });

        const todayKey = toDateKey(new Date());
        const legendByPosition = new Map();
        const days = [];
        for (let index = 0; index < weeks * 7; index++) {
            const date = new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + index);
            const key = toDateKey(date);
            const isInMonth = date.getMonth() === this.viewMonth;
            const dayShifts = byDay.get(key) || [];
            const longLabel = LONG_DAY_FORMAT.format(date);
            const overflowCount = Math.max(0, dayShifts.length - MAX_VISIBLE_SHIFTS);
            if (isInMonth) {
                dayShifts.forEach((shift) => {
                    legendByPosition.set(shift.positionId, { name: shift.positionName, color: shift.color });
                });
            }
            let className = 'day';
            if (!isInMonth) {
                className += ' day--outside';
            }
            if (key === todayKey) {
                className += ' day--today';
            }
            if (dayShifts.length === 0) {
                className += ' day--empty';
            }
            days.push({
                key,
                dayNumber: date.getDate(),
                longLabel: key === todayKey ? `${longLabel} (today)` : longLabel,
                isInMonth,
                className,
                hasShifts: dayShifts.length > 0,
                shifts: dayShifts.map((shift, position) => ({
                    ...shift,
                    itemClass: position >= MAX_VISIBLE_SHIFTS ? 'shift-item shift-item--overflow' : 'shift-item'
                })),
                hasOverflow: overflowCount > 0,
                overflowCount,
                moreFocusKey: `more:${key}`,
                moreAriaLabel: `Show ${overflowCount} more ${overflowCount === 1 ? 'shift' : 'shifts'} on ${longLabel}`
            });
        }
        this.days = days;
        this.legend = [...legendByPosition.entries()]
            .map(([id, entry]) => ({
                id,
                name: entry.name,
                swatchClass: `swatch color-${entry.color}`
            }))
            .sort((a, b) => a.name.localeCompare(b.name));
    }

    handlePrevious() {
        this.moveMonth(-1);
    }
    handleNext() {
        this.moveMonth(1);
    }
    handleToday() {
        const today = new Date();
        this.viewYear = today.getFullYear();
        this.viewMonth = today.getMonth();
        this.rebuild();
        this.loadShifts();
    }
    moveMonth(step) {
        const target = new Date(this.viewYear, this.viewMonth + step, 1);
        this.viewYear = target.getFullYear();
        this.viewMonth = target.getMonth();
        this.rebuild();
        this.loadShifts();
    }

    // ---------- loading data ----------

    async loadFilterOptions() {
        try {
            const options = await getFilterOptions();
            this.positionOptions = options.positions || [];
            this.initiativeOptions = options.initiatives || [];
        } catch {
            this.positionOptions = [];
            this.initiativeOptions = [];
        }
    }

    async loadShifts(silent = false) {
        const requestId = ++this._loadRequestId;
        if (!silent) {
            this.isLoading = true;
        }
        this.loadError = undefined;
        const { gridStart, weeks } = this.gridRange();
        const rangeStart = new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() - 1);
        const rangeEnd = new Date(gridStart.getFullYear(), gridStart.getMonth(), gridStart.getDate() + weeks * 7);
        try {
            const result = await getShifts({ rangeStart: toDateKey(rangeStart), rangeEnd: toDateKey(rangeEnd) });
            if (requestId !== this._loadRequestId) {
                return;
            }
            this.shifts = (result || []).map(enrichShift);
        } catch (error) {
            if (requestId !== this._loadRequestId) {
                return;
            }
            this.shifts = [];
            this.loadError = readError(error, MSG_LOAD_FAILED);
        }
        this.isLoading = false;
        this.rebuild();
    }

    // ---------- pop-ups ----------

    get isDialogOpen() {
        return !!this.dialogType;
    }
    get isDayDialog() {
        return this.dialogType === 'day';
    }
    get isShiftDialog() {
        return this.dialogType === 'shift';
    }
    get dialogTitle() {
        if (this.isDayDialog) {
            const day = this.days.find((item) => item.key === this.dayKey);
            return day ? `Shifts on ${day.longLabel}` : 'Shifts';
        }
        return 'Shift details';
    }
    get dayDialogShifts() {
        const day = this.days.find((item) => item.key === this.dayKey);
        return day ? day.shifts.map((shift) => ({ ...shift, itemClass: 'shift-item' })) : [];
    }
    get isSignedUp() {
        return !!this.detail && this.detail.alreadySignedUp === true;
    }
    get showBlockedMessage() {
        return !!this.detail && !this.isSignedUp && !!this.detail.blockedMessage;
    }
    get signUpDisabled() {
        return !this.detail || this.detail.canSignUp !== true || this.signingUp || this.detailLoading;
    }
    get signUpLabel() {
        return this.signingUp ? 'Signing you up...' : 'Sign-Up For Shift';
    }

    handleMoreClick(event) {
        this.dayKey = event.currentTarget.dataset.day;
        this._returnFocusKey = event.currentTarget.dataset.focusKey;
        this.dialogType = 'day';
        this._focusDialog = true;
    }

    handleShiftClick(event) {
        const shiftId = event.currentTarget.dataset.id;
        if (!this.isDayDialog) {
            this._returnFocusKey = event.currentTarget.dataset.focusKey;
        }
        this.openShift(shiftId);
    }

    async openShift(shiftId) {
        const requestId = ++this._detailRequestId;
        this.dialogType = 'shift';
        this.selectedShiftId = shiftId;
        this.detail = undefined;
        this.detailError = undefined;
        this.successMessage = undefined;
        this.signUpError = undefined;
        this.detailLoading = true;
        this._focusDialog = true;
        try {
            const result = await getShiftDetail({ shiftId });
            if (requestId !== this._detailRequestId) {
                return;
            }
            this.detail = this.prepareDetail(result);
        } catch (error) {
            if (requestId !== this._detailRequestId) {
                return;
            }
            this.detailError = readError(error, MSG_DETAIL_FAILED);
        }
        this.detailLoading = false;
    }

    prepareDetail(result) {
        const shift = result.shift;
        const start = new Date(shift.startDateTime);
        const end = new Date(shift.endDateTime);
        return {
            ...result,
            shift,
            descriptionText: result.description || 'No description has been added for this shift.',
            initiativeText: shift.initiativeName || 'None',
            startLabel: FULL_FORMAT.format(start),
            endLabel: FULL_FORMAT.format(end),
            capacityText: shift.isUnlimited ? 'Unlimited' : String(shift.maximumAttendees),
            remainingText: shift.isUnlimited ? 'Unlimited' : String(shift.remainingCapacity),
            hasNoQualifications: !result.qualifications || result.qualifications.length === 0,
            qualifications: (result.qualifications || []).map((qualification, index) => {
                const isMet = qualification.status === 'Met';
                return {
                    ...qualification,
                    key: `${qualification.name}-${index}`,
                    typeLabel: qualification.qualificationType === 'Examination' ? 'Examination' : 'Competency',
                    iconName: isMet ? 'utility:success' : 'utility:error',
                    iconVariant: isMet ? 'success' : 'error',
                    statusClass: isMet ? 'status status--met' : 'status status--unmet'
                };
            })
        };
    }

    async handleSignUp() {
        if (this.signUpDisabled) {
            return;
        }
        this.signingUp = true;
        this.signUpError = undefined;
        this.successMessage = undefined;
        try {
            const result = await signUp({ shiftId: this.selectedShiftId });
            this.detail = this.prepareDetail(result);
            this.successMessage = MSG_SIGNED_UP;
            const updated = enrichShift(result.shift);
            this.shifts = this.shifts.map((shift) => (shift.id === updated.id ? updated : shift));
            this.rebuild();
        } catch (error) {
            this.signUpError = readError(error, MSG_SIGN_UP_FAILED);
            await this.refreshAfterFailedSignUp();
        }
        this.signingUp = false;
        this._focusDialog = true;
    }

    async refreshAfterFailedSignUp() {
        try {
            const result = await getShiftDetail({ shiftId: this.selectedShiftId });
            this.detail = this.prepareDetail(result);
        } catch {
            // The error message above already tells the volunteer what happened.
        }
        this.loadShifts(true);
    }

    handleCloseDialog() {
        this._detailRequestId++;
        this._pendingFocusKey = this._returnFocusKey;
        this.dialogType = undefined;
        this.detail = undefined;
        this.detailError = undefined;
        this.successMessage = undefined;
        this.signUpError = undefined;
        this.detailLoading = false;
    }

    handleBackdropClick(event) {
        if (event.target === event.currentTarget) {
            this.handleCloseDialog();
        }
    }

    handleDialogKeydown(event) {
        if (event.key === 'Escape') {
            event.stopPropagation();
            this.handleCloseDialog();
            return;
        }
        if (event.key !== 'Tab') {
            return;
        }
        const focusable = [...this.template.querySelectorAll('.dialog button:not([disabled])')];
        if (focusable.length === 0) {
            event.preventDefault();
            this.template.querySelector('.dialog').focus();
            return;
        }
        const first = focusable[0];
        const last = focusable[focusable.length - 1];
        const active = this.template.activeElement;
        if (event.shiftKey && (active === first || active === this.template.querySelector('.dialog'))) {
            event.preventDefault();
            last.focus();
        } else if (!event.shiftKey && active === last) {
            event.preventDefault();
            first.focus();
        }
    }
}
