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
    }, 200);

    const context = await window.OpenProject.getPluginContext();
    this.timezoneService = context.services.timezone;

    document.addEventListener('date-picker:flatpickr-dates-changed', this.handleFlatpickrDatesChangedBound);
    document.addEventListener('turbo:before-stream-render', this.updateFlatpickrCalendarBound);
  }

  disconnect() {
    document.removeEventListener('date-picker:flatpickr-dates-changed', this.handleFlatpickrDatesChangedBound);
    document.removeEventListener('turbo:before-stream-render', this.updateFlatpickrCalendarBound);
  }

  private updateFlatpickrCalendar() {
    const dates:Date[] = _.compact([
      this.toDate(this.startDateTarget.value), this.toDate(this.finishDateTarget.value),
    ]);
    const ignoreNonWorkingDays = false;
    const mode = this.mode();

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

  private mode():'single'|'range' {
    if (this.startDateTarget.disabled) {
      return 'single';
    }
    return 'range';
  }

  handleFlatpickrDatesChanged(event:CustomEvent<{ dates:Date[] }>) {
    const dates = event.detail.dates;
    this.startDateTarget.value = this.dateToIso(dates[0]);
    this.finishDateTarget.value = this.dateToIso(dates[1]);
    this.previewForm();
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
