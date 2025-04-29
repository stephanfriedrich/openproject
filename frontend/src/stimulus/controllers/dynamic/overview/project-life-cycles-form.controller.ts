/*
 * -- copyright
 * OpenProject is an open source project management software.
 * Copyright (C) the OpenProject GmbH
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License version 3.
 *
 * OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
 * Copyright (C) 2006-2013 Jean-Philippe Lang
 * Copyright (C) 2010-2013 the ChiliProject Team
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 * See COPYRIGHT and LICENSE files for more details.
 * ++
 */

import { TimezoneService } from 'core-app/core/datetime/timezone.service';
import FormPreviewController from '../../form-preview.controller';
import {
  debounce,
  DebouncedFunc,
} from 'lodash';

export default class ProjectLifeCyclesFormController extends FormPreviewController {
  private timezoneService:TimezoneService;
  private handleFlatpickrDatesChangedBound = this.handleFlatpickrDatesChanged.bind(this);
  private updateFlatpickrCalendarBound = this.updateFlatpickrCalendar.bind(this);
  private previewForm:DebouncedFunc<() => void>;

  static targets = ['startDate', 'finishDate', 'duration'];

  declare readonly startDateTarget:HTMLInputElement;
  declare readonly finishDateTarget:HTMLInputElement;
  declare readonly durationTarget:HTMLInputElement;

  async connect() {
    super.connect();

    this.previewForm = debounce(() => {
      void this.submit();
    }, 300);

    const context = await window.OpenProject.getPluginContext();
    this.timezoneService = context.services.timezone;

    document.addEventListener('date-picker:flatpickr-dates-changed', this.handleFlatpickrDatesChangedBound);
    document.addEventListener('turbo:before-stream-render', this.updateFlatpickrCalendarBound);

    const activeElement = document.activeElement as HTMLInputElement;
    if (activeElement && this.enabledDateInputFields.includes(activeElement)) {
      this.highlightField(activeElement);
    }
  }

  disconnect() {
    document.removeEventListener('date-picker:flatpickr-dates-changed', this.handleFlatpickrDatesChangedBound);
    document.removeEventListener('turbo:before-stream-render', this.updateFlatpickrCalendarBound);
  }

  onHighlightField(e:Event) {
    const fieldToHighlight = e.target as HTMLInputElement;
    if (fieldToHighlight) {
      this.highlightField(fieldToHighlight);
    }
  }

  private updateFlatpickrCalendar() {
    const dates:Date[] = _.compact(this.dateInputFields.map((field) => this.toDate(field.value)));
    const ignoreNonWorkingDays = false;
    const mode = this.mode;

    document.dispatchEvent(
      new CustomEvent('date-picker:flatpickr-set-values', {
        detail: {
          dates,
          ignoreNonWorkingDays,
          mode,
        },
      }),
    );
  }

  private get mode():'single'|'range' {
    return 'range';
  }

  highlightField(field:HTMLInputElement) {
    this.clearHighLight();
    field.classList.add('op-datepicker-modal--date-field_current');
    this.updateFlatpickrCalendar();
    window.setTimeout(() => {
      // For mobile, we have to make sure that the active field is scrolled into view after the keyboard is opened
      field.scrollIntoView(true);
    }, 300);
  }

  handleFlatpickrDatesChanged(event:CustomEvent<{ dates:Date[] }>) {
    const dates = event.detail.dates;

    if (dates.length === 1) {
      if ((this.highlightedField === this.finishDateTarget) || this.startDateTarget.disabled) {
        this.finishDateTarget.value = this.dateToIso(dates[0]);
        if (this.startDateTarget.disabled) {
          this.clearHighLight();
        }
      } else {
        this.startDateTarget.value = this.dateToIso(dates[0]);
      }
    } else {
      this.dateInputFields
        .forEach((field, index) => {
          if (!field.disabled) {
            field.value = this.dateToIso(dates[index]);
          }
        });
      this.clearHighLight();
    }
    this.updateFlatpickrCalendar();
    this.previewForm();
  }

  private get dateInputFieldsToUpdate():HTMLInputElement[] {
    if (this.highlightedField) {
      return [this.highlightedField];
    }
    return this.dateInputFields;
  }

  private get dateInputFields():HTMLInputElement[] {
    return [this.startDateTarget, this.finishDateTarget];
  }

  private get enabledDateInputFields():HTMLInputElement[] {
    return this.dateInputFields.filter((field) => !field.disabled);
  }

  private get highlightedField():HTMLInputElement|undefined {
    const field = this.dateInputFields.find(
      (el) => el.classList.contains('op-datepicker-modal--date-field_current'),
    );

    return field;
  }

  private clearHighLight() {
    this.dateInputFields
        .forEach((el) => el.classList.remove('op-datepicker-modal--date-field_current'));
  }

  private dateToIso(date:Date|null):string {
    if (date) {
      return this.timezoneService.utcDateToISODateString(date);
    }
    return '';
  }

  private toDate(date:string|null):Date|null {
    if (date && /^\d{4}-\d{2}-\d{2}$/.test(date)) {
      return new Date(date);
    }
    return null;
  }
}
