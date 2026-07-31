// Auxiliary file for SPIKE.md — full verbatim copy for reference.
// Source: ~/Projects/4Shark/app-webclient/src/app/variable/variable.component.ts
// Repo commit at capture time: f1920fb6bed46c477028113d90df1994ad48f278
// Relevant to demand 1 — this is the ESTABLISHED generic listing pattern
// (relay-cursor infinite scroll + Filter model synced to route.queryParams)
// that ~90 other entity listings in the app now use (per CHANGELOG 1.275.0,
// see roadmap-barigui_changelog_1.md). The dashboard ranking widget
// (roadmap-barigui_excerpt_1.ts / _2.html) does NOT use this pattern — it
// uses a plain component-state slice (usersVisibleCount) over a backend
// array capped at 10 records. A new "ranking full list" page for demand 1
// would be the first place this pattern is applied to a Mongo-aggregation
// resolver rather than an ActiveRecord-backed one.

import { ActivatedRoute, Router } from '@angular/router';
import { Component, HostListener, OnDestroy, OnInit } from '@angular/core';
import { noop as _noop } from 'lodash-es';
import { Subscription } from 'rxjs';

import { AccessControlService } from '@app/core/access-control/access-control.service';
import { Company } from '@app/company/company.model';
import { CompanyService } from '@app/company/company.service';
import { Filter } from '@app/shared/filter.model';
import { Permissions } from '@app/core/access-control/permissions';
import { TranslateService } from '@ngx-translate/core';
import { Variable } from '@app/variable/variable.model';
import { VariableDisableService } from './variable-disable.service';
import { VariableEnableService } from './variable-enable.service';
import { VariablePermissionsService } from './variable-permissions.service';
import { VariableService } from './variable.service';

@Component({
  standalone: false,
  selector: 'app-variable',
  templateUrl: './variable.component.html',
  styleUrls: ['./variable.component.scss'],
})
export class VariableComponent implements OnInit, OnDestroy {
  activeMenuId: string | null = null;
  companies: Company[];
  company: Company;
  companyIdErrorMessage = '';
  emptyMessage: boolean;
  endCursor: string;
  filter: Filter = new Filter({});
  lastPageLength = 0;
  loading: boolean;
  loadingMore: boolean;
  loadingCompanies: boolean;
  message: string | null = null;
  pageLength = 9;
  permissions = Permissions;
  showFilters = false;
  variablePermissions: string[] = [];
  variables: Variable[];
  private variablesSubscription: Subscription | undefined;

  constructor(
    private companyService: CompanyService,
    private route: ActivatedRoute,
    private router: Router,
    private translateService: TranslateService,
    private variableDisableService: VariableDisableService,
    private variableEnableService: VariableEnableService,
    private variablePermissionsService: VariablePermissionsService,
    private variableService: VariableService,
    public accessControlService: AccessControlService,
  ) {}

  ngOnInit() {
    if (!this.accessControlService.hasPermission('variablesListing')) {
      this.router.navigateByUrl(this.accessControlService.home());
    }

    this.route.queryParams.subscribe((params: Filter) => {
      this.filter = new Filter(params);

      if (this.filter.enabled === undefined) {
        this.filter.enabled = 'true';
      }

      if (this.filter.calculation === undefined) {
        this.filter.calculation = '';
      }

      if (this.filter.frequency === undefined) {
        this.filter.frequency = '';
      }

      if (this.filter.type === undefined) {
        this.filter.type = '';
      }

      if (this.filter.dataType === undefined) {
        this.filter.dataType = '';
      }

      // NOTE: pagination state (endCursor) is reset here alongside the filter
      // values — the filter VALUES persist through route.queryParams across a
      // back-navigation, but the SCROLL DEPTH does not. Cited for demand 6.
      this.endCursor = undefined;
      this.variables = undefined;
      this.loading = true;
      this.getVariablePermissions();
      this.getVariables();
    });

    if (this.accessControlService.hasPermission('companiesListing')) {
      this.getCompanies();
    }
  }

  handleScroll = (scrolled: boolean) => {
    if (scrolled) {
      this.getVariables();
    } else {
      _noop();
    }
  };

  hasMore() {
    return this.variables && this.variables.length > 0 && this.lastPageLength >= this.pageLength;
  }

  getVariablePermissions() {
    this.variablePermissionsService.get().valueChanges.subscribe((response: any) => {
      if (!response?.data || Object.keys(response.data).length === 0) {
        return;
      }

      this.variablePermissions = response.data.variablePermissions.permissions;
    });
  }

  getVariables() {
    this.loadingMore = true;

    if (this.variablesSubscription) {
      this.variablesSubscription.unsubscribe();
    }

    this.variablesSubscription = this.variableService
      .list(this.endCursor, this.filter)
      .valueChanges.subscribe((response: any) => {
        if (!response?.data || Object.keys(response.data).length === 0) {
          return;
        }

        const newNodes = response.data.variables.nodes;
        this.lastPageLength = newNodes.length;

        if (this.lastPageLength > 0) {
          if (this.variables) {
            const allNodes = [...this.variables, ...newNodes];
            this.variables = allNodes;
          } else {
            this.variables = newNodes;
          }

          this.endCursor = response.data.variables.pageInfo.endCursor;
        } else if (!this.variables) {
          this.variables = [];
        }

        this.loading = false;
        this.loadingMore = false;
      });
  }

  ngOnDestroy() {
    if (this.variablesSubscription) {
      this.variablesSubscription.unsubscribe();
    }
  }

  noVariables() {
    if (this.loading === false && this.variables && this.variables.length === 0) {
      return true;
    } else {
      return false;
    }
  }

  getCompanies(value = '', id: string = this.filter.companyId) {
    this.loadingCompanies = true;
    const companyFilter = new Filter({ id: id, search: value });

    this.companyService.list('', companyFilter).valueChanges.subscribe((response: any) => {
      if (!response?.data || Object.keys(response.data).length === 0) {
        return;
      }

      if (response.data.companies.nodes.length > 0) {
        this.companies = response.data.companies.nodes;
        this.companyIdErrorMessage = '';
      } else {
        this.companies = [];
        this.companyIdErrorMessage = this.translateService.instant('company.page.search.without_company');
      }

      this.loadingCompanies = false;
    });
  }

  disabledButton(event: any) {
    const variables: Record<string, any> = { id: event };
    this.variableDisableService
      .mutation(
        'variableDisableService',
        `mutation DisableVariable($id: ID!) {
          disableVariable(id: $id) {
            id
          }
        }`,
        variables,
      )
      .subscribe(() => {
        this.showMessage(this.translateService.instant('variable.page.success_disabled'), true);
      });
  }

  enabledButton(event: any) {
    const variables: Record<string, any> = { id: event };
    this.variableEnableService
      .mutation(
        'variableEnableService',
        `mutation EnableVariable($id: ID!) {
          enableVariable(id: $id) {
            id
          }
        }`,
        variables,
      )
      .subscribe(() => {
        this.showMessage(this.translateService.instant('variable.page.success_enabled'), true);
      });
  }

  clearCompany() {
    this.filter.companyId = null;
    this.company = null;
  }

  fullTextSearch(event: Event): void {
    const inputElement = event.target as HTMLInputElement;
    this.filter.search = inputElement.value;
  }

  selectCompany(event: { id: string }): void {
    this.filter.companyId = event.id;
  }

  selectCalculation(event: Event): void {
    const selectElement = event.target as HTMLSelectElement;
    this.filter.calculation = selectElement.value;
  }

  selectDataType(event: Event): void {
    const selectElement = event.target as HTMLSelectElement;
    this.filter.dataType = selectElement.value;
  }

  selectEnabled(event: Event): void {
    const target = event.target as HTMLSelectElement;
    this.filter.enabled = target.value;
  }

  selectFrequency(event: Event): void {
    const selectElement = event.target as HTMLSelectElement;
    this.filter.frequency = selectElement.value;
  }

  selectType(event: Event): void {
    const selectElement = event.target as HTMLSelectElement;
    this.filter.type = selectElement.value;
  }

  toggleFilters(): void {
    this.showFilters = !this.showFilters;
  }

  toggleMenu(variable: Variable) {
    this.activeMenuId = this.activeMenuId === String(variable.id) ? null : String(variable.id);
  }

  stopPropagation(event: Event): void {
    event.stopPropagation();
  }

  closeMenu() {
    this.activeMenuId = null;
  }

  @HostListener('document:click', ['$event'])
  onDocumentClick(event: Event) {
    const target = event.target as HTMLElement;
    if (!target.closest('.menu-container')) {
      this.closeMenu();
    }
  }

  showMessage(text: string, reloadAfter = false) {
    this.message = text;
    setTimeout((): void => {
      this.message = null;
      if (reloadAfter) {
        window.location.reload();
      }
    }, 2000);
  }
}
