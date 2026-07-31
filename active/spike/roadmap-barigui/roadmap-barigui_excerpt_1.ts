// Auxiliary file for SPIKE.md — full verbatim copy for reference.
// Source: ~/Projects/4Shark/app-webclient/src/app/dashboard/plan/dashboard-plan.component.ts
// Repo commit at capture time: f1920fb6bed46c477028113d90df1994ad48f278 (2026-07-30 12:49:23 -0300)
// Relevant to demands 1 (ranking), 2 (indicator totalizer), 3 (seller screen cleanup).

import { ActivatedRoute, Router } from '@angular/router';
import { AfterViewInit, ChangeDetectorRef, Component, ElementRef, OnDestroy, OnInit, ViewChild } from '@angular/core';
import { formatCurrency } from '@angular/common';
import { TranslateService } from '@ngx-translate/core';

import { Calendar } from '@app/calendar/calendar.model';
import { CalendarService } from '@app/calendar/calendar.service';
import { DealDataset } from '@app/deal-dataset/deal-dataset.model';
import { DealDatasetService } from '@app/deal-dataset/deal-dataset.service';
import { Filter } from '@app/shared/filter.model';
import { GoalDataset } from '@app/goal-dataset/goal-dataset.model';
import { GoalDatasetService } from '@app/goal-dataset/goal-dataset.service';
import { IncentiveDataset } from '@app/incentive-dataset/incentive-dataset.model';
import { IndicatorDataset } from '@app/indicator-dataset/indicator-dataset.model';
import { IndicatorDatasetService } from '@app/indicator-dataset/indicator-dataset.service';
import { MeService } from '@app/me/me.service';
import { Period } from '@app/period/period.model';
import { PeriodService } from '@app/period/period.service';
import { Plan } from '@app/plan/plan.model';
import { PlanStatement } from '@app/plan-statement/plan-statement.model';
import { PremiumService } from '@app/premium/premium.service';
import { Statement } from '@app/statement/statement.model';
import { TemporaryProfileService } from '@app/profile/temporary-profile.service';
import { User } from '@app/user/user.model';
import { UserAggregatedUserCommissionDatasetsService } from '@app/user-aggregated-user-commission-datasets/user-aggregated-user-commission-datasets.service';
import { UserCommissionDataset } from '@app/user-commission-dataset/user-commission-dataset.model';
import { UserCommissionDatasetService } from '@app/user-commission-dataset/user-commission-dataset.service';
import { Variable } from '@app/variable/variable.model';
import { VariableService } from '@app/variable/variable.service';
import { environment } from '@env/environment';
import { filter, forkJoin, Observable, take } from 'rxjs';

@Component({
  standalone: false,
  selector: 'app-home',
  templateUrl: './dashboard-plan.component.html',
  styleUrls: ['./dashboard-plan.component.scss'],
})
export class DashboardPlanComponent implements OnInit, AfterViewInit, OnDestroy {
  averageMoneyUser: number;
  calendar: Calendar;
  calendarId: string;
  currency = environment.currency;
  currencyLocale = environment.currencyLocale;
  currencyNumberRepresentation = environment.currencyNumberRepresentation;
  currencySymbol = environment.currencySymbol;
  currentUserSeat: string;
  calendarClosesToday: boolean = false;
  daysUntilCalendarCloses: string;
  @ViewChild('dealChartContainer') dealChartContainerRef: ElementRef;
  dealChartResizeObserver: ResizeObserver;
  dealChartView: [number, number] | undefined;
  dealDatasets: DealDataset[];
  dealDateRangeDays: number | null = null;
  deals: any;
  dealsExpanded: boolean = false;
  filter: Filter = new Filter({});
  goalCalculationModule: boolean;
  goalDatasets: GoalDataset[];
  indicatorDatasets: IndicatorDataset[];
  incentiveDatasets: IncentiveDataset[];
  lineCharts: any;
  loadingGoalDatasets: boolean;
  loadingProfiles: boolean;
  loadingPeriods: boolean;
  loadingPlans: boolean;
  period: Period;
  periodId: string;
  periodIdErrorMessage = '';
  periods: Period[] = [];
  plan: Plan;
  planGoal: any;
  planGoalAbove: boolean = false;
  planGoalDifference: string | null = null;
  planId: string;
  planIdErrorMessage = '';
  plans: Plan[];
  selectedUser: User;
  selectedUserMoney: number;
  selectedUserPlanStatement: PlanStatement;
  selectedUserRanking: number;
  selectedUserStatement: Statement;
  sort: string;
  statement: Statement;
  totalMoneyUserAggregatedUserCommissionDatasets: number;
  totalUserAggregatedUserCommissionDatasets?: number;
  user: User;
  userAggregatedUserCommissionDatasets?: UserCommissionDataset[];
  userAggregatedUserCommissionDatasetsAboveAverage: number;
  userAggregatedUserCommissionDatasetsBelowAverage: number;
  userCommissionDatasets: [UserCommissionDataset];
  userId: string;
  userSort: string;
  usersVisibleCount: number;
  variableIds: any[];
  variables: Variable[];
  visibleCount = 3;

  get loading(): boolean {
    return this.loadingGoalDatasets || this.loadingProfiles;
  }

  constructor(
    private calendarService: CalendarService,
    private changeDetectorRef: ChangeDetectorRef,
    private dealDatasetService: DealDatasetService,
    private goalDatasetService: GoalDatasetService,
    private indicatorDatasetService: IndicatorDatasetService,
    private meService: MeService,
    private periodService: PeriodService,
    private premiumService: PremiumService,
    private route: ActivatedRoute,
    private temporaryProfileService: TemporaryProfileService,
    private userAggregatedUserCommissionDatasetsService: UserAggregatedUserCommissionDatasetsService,
    private userCommissionDatasetService: UserCommissionDatasetService,
    private variableService: VariableService,
    public translateService: TranslateService,
  ) {}

  ngOnInit() {
    this.scrollToTop();
    this.visibleCount = 3;
    this.usersVisibleCount = 6;
    this.loadingGoalDatasets = true;
    if (this.userSort === undefined) {
      this.userSort = 'highest_value';
    }
    if (this.sort == undefined) {
      this.sort = 'highest_value';
    }
    if (this.userId !== undefined) {
      this.selectedUser = new User({ id: Number(this.userId) });
    }

    this.meService.query('me', `query { me { seat { type } } }`).valueChanges.subscribe((response: any) => {
      if (!response?.data || Object.keys(response.data).length === 0) {
        return;
      }

      this.currentUserSeat = response.data.me.seat.type;
    });

    this.route.params.subscribe((params: any) => {
      this.periodId = params.periodId;
      this.planId = params.planId;
      this.userId = params.userId;
      this.calendarId = params.calendarId;

      if (this.periodId) {
        this.getPeriod();
      } else {
        this.getCalendar();
      }

      this.getUserCommissionDatasets();
      this.getUserAggregatedUserCommissionDatasets();
    });
  }

  ngAfterViewInit(): void {
    this.initDealChartResize();
  }

  ngOnDestroy(): void {
    this.dealChartResizeObserver?.disconnect();
  }

  private initDealChartResize(): void {
    if (!this.dealChartContainerRef) {
      return;
    }
    this.dealChartResizeObserver = new ResizeObserver(() => {
      this.dealChartView = [this.dealChartContainerRef.nativeElement.offsetWidth - 60, 180];
      this.changeDetectorRef.detectChanges();
    });
    this.dealChartResizeObserver.observe(this.dealChartContainerRef.nativeElement);
  }

  selectUser(userCommissionDataset: UserCommissionDataset) {
    if (this.userId !== userCommissionDataset?.user?.id?.toString()) {
      this.averageMoneyUser = userCommissionDataset.averageMoneyUser;
      this.selectedUserMoney = userCommissionDataset.money;
      this.selectedUserPlanStatement = userCommissionDataset.planStatement;
      this.selectedUserStatement = userCommissionDataset.statement;
      this.selectedUserRanking = userCommissionDataset.ranking;
      this.selectedUser = new User(userCommissionDataset.user);
      this.user = new User(userCommissionDataset.user);
      this.userId = userCommissionDataset?.user?.id?.toString();
      this.getUserCommissionDatasets();
      this.scrollToTop();
    }
  }

  clearUser() {
    this.selectedUser = undefined;
    this.selectedUserRanking = undefined;
    this.selectedUserMoney = undefined;
    this.averageMoneyUser = undefined;
    this.selectedUserPlanStatement = undefined;
    this.selectedUserStatement = undefined;
    this.user = undefined;
    this.userId = undefined;
    this.getUserCommissionDatasets();
    this.getUserAggregatedUserCommissionDatasets();
    this.scrollToTop();
  }

  scrollToTop(): void {
    window.scrollTo(0, 0);
  }

  progressBarValue(goal: number, value: number, baseline: any) {
    const goal_interval = goal - baseline;
    const user_interval = value - baseline;
    let reach = 0;

    if (goal_interval !== 0) {
      reach = user_interval / goal_interval;
    }

    return Number((reach * 100).toFixed(2));
  }

  yAxisTickFormattingPercent(value: any) {
    if (value < 1) {
      return value * 100 + '%';
    } else {
      return value;
    }
  }

  yAxisTickFormattingDuration(value: number) {
    const hours = Math.floor(value / 3600);
    value %= 3600;
    const minutes = Math.floor(value / 60);

    return hours + 'h' + minutes + 'm';
  }

  roundedProgressBarValue(formattedGoal: number, formattedValue: number, formattedBaseline: number): number {
    const goal = formattedGoal;
    const value = formattedValue;
    const baseline = formattedBaseline;
    const progressValue = ((value - baseline) / (goal - baseline)) * 100;
    return Math.round(progressValue);
  }

  trackByFn(index: number, item: any): any {
    return item.id || index;
  }

  incentiveDatasetToggleExpanded(incentiveDataset: IncentiveDataset): void {
    incentiveDataset.expanded = !incentiveDataset.expanded;
  }

  toggleGoalCardActive(event: Event): void {
    const button = event.target as HTMLElement;
    const parent = button.closest('.goal-widget-box');

    if (parent) {
      parent.classList.toggle('active');
      parent.classList.toggle('flipped');
    }
  }

  loadMore(): void {
    const increment = 3;
    this.visibleCount += increment;
  }

  loadMoreUsers(): void {
    this.usersVisibleCount += 5;
  }

  getGoalDatasets() {
    const variables: Record<string, any> = {};

    if (this.periodId) {
      variables.periodId = this.periodId;
    }

    if (this.planId) {
      variables.planId = this.planId;
    }

    if (this.userId) {
      variables.userId = this.userId;
    }

    const goalDatasetQuery = `query GoalDatasets($periodId: ID, $planId: ID!, $userId: ID) {
      goalDatasets(
        periodId: $periodId
        planId: $planId
        userId: $userId
      ) {
        nodes {
          baseline
          count
          formattedBaseline
          formattedGoal
          formattedValue
          goal
          lastUpdateAt
          value
          variableId
          variableName
          variableType
        }
      }
    }`;

    this.goalDatasetService.query('goalDataset', goalDatasetQuery, variables).valueChanges.subscribe(
      (response: any) => {
        if (!response?.data || Object.keys(response.data).length === 0) {
          return;
        }

        if (response.data.goalDatasets.nodes.length > 0) {
          this.goalDatasets = response.data.goalDatasets.nodes;
        } else {
          this.goalDatasets = [];
        }

        this.loadingGoalDatasets = false;

        this.getTemporaryProfiles();
      },
      (error: any) => {
        console.error('Error fetching data:', error);
        this.loadingGoalDatasets = false;
      },
    );
  }

  getUserCommissionDatasets() {
    const variables: Record<string, any> = {};

    if (this.planId) {
      variables.planId = this.planId;
    }

    if (this.periodId) {
      variables.periodId = this.periodId;
    }

    if (this.userId) {
      variables.userId = this.userId;
    }

    const userCommissionDatasetsQuery = `query UserCommissionDatasets($planId: ID, $periodId: ID, $userId: ID) {
      userCommissionDatasets(
        planId: $planId
        periodId: $periodId
        userId: $userId
      ) {
        nodes {
          commissioningDatasets {
            incentiveId
            name
            type
            value
          }
          money
          plan {
            calendar {
              endsAt
              id
              name
              startsAt
            }
            company {
              goalCalculationModule
            }
            id
            name
            owner {
              id
              name
              profile {
                id
              }
            }
            responsible {
              id
              name
              profile {
                id
              }
            }
            totalAcceptedStatements
            totalStatements
          }
          planStatementId
          points
        }
      }
    }`;

    this.userCommissionDatasetService
      .query('userCommissionDataset', userCommissionDatasetsQuery, variables)
      .valueChanges.subscribe(
        (response: any) => {
          if (!response?.data || Object.keys(response.data).length === 0) {
            return;
          }

          this.userCommissionDatasets = response.data.userCommissionDatasets.nodes;

          if (this.userCommissionDatasets.length > 0) {
            this.plan = new Plan(this.userCommissionDatasets[0]?.plan);
            this.calendar = new Calendar(this.userCommissionDatasets[0]?.plan?.calendar);
          } else {
            this.plan = undefined;
            this.calendar = undefined;
          }

          this.getDealDatasets();
          this.getIncentiveDatasets();
          this.getGoalDatasets();
        },
        (error: any) => {
          console.error('Error fetching data:', error);
        },
      );
  }

  getIncentiveDatasets() {
    const variables: Record<string, any> = {};

    if (this.planId) {
      variables.planId = this.planId;
    }

    if (this.periodId) {
      variables.periodId = this.periodId;
    }

    if (this.userId) {
      variables.userId = this.userId;
    }

    const premiumQuery = `query Premium($planId: ID, $periodId: ID, $userId: ID) {
      premium(
        planId: $planId
        periodId: $periodId
        userId: $userId
      ) {
        nodes {
          commissionType
          name
          ruleDatasets {
            description
            value
            ruleValue
          }
          value
        }
      }
    }`;

    this.premiumService.query('premium', premiumQuery, variables).valueChanges.subscribe(
      (response: any) => {
        if (!response?.data || Object.keys(response.data).length === 0) {
          return;
        }

        this.incentiveDatasets = response.data.premium.nodes;
      },
      (error: any) => {
        console.error('Error fetching data:', error);
      },
    );
  }

  dealBoxTitle() {
    switch (this.plan.type) {
      case 'CallsPlan': {
        return this.translateService.instant('call.other');
      }
      case 'CreditRecoveryPlan': {
        return this.translateService.instant('credit_recovery.other');
      }
      case 'ServiceSalesPlan': {
        return this.translateService.instant('service_sale.other');
      }
      default: {
        return this.translateService.instant('sale.other');
      }
    }
  }

  getDealDatasets() {
    if (!this.calendar) {
      return;
    }

    const variables: Record<string, any> = {};

    if (this.calendar?.endsAt) {
      variables.endsAt = this.calendar.endsAt;
    }

    if (this.planId) {
      variables.planId = this.planId;
    }

    if (this.calendar?.startsAt) {
      variables.startsAt = this.calendar.startsAt;
    }

    if (this.userId) {
      variables.userId = this.userId;
    }

    const dealDatasetQuery = `query DealDatasets($endsAt: String!, $planId: ID, $startsAt: String!, $userId: ID) {
      dealDatasets(
        endsAt: $endsAt
        planId: $planId
        startsAt: $startsAt
        userId: $userId
      ) {
        nodes {
          date
          type
          value
        }
      }
    }`;

    this.dealDatasetService.query('dealDataset', dealDatasetQuery, variables).valueChanges.subscribe(
      (response: any) => {
        if (!response?.data || Object.keys(response.data).length === 0) {
          return;
        }

        const nodes = response.data.dealDatasets.nodes;
        if (!nodes.some((deal: any) => deal.value > 0)) {
          return;
        }
        this.dealDatasets = nodes;
        this.processDealChart();
      },
      (error: any) => {
        console.error('Error fetching data:', error);
      },
    );
  }

  processDealChart() {
    const totalValue = this.dealDatasets.reduce((sum: number, deal: any) => {
      return sum + deal.value;
    }, 0);

    const timestamps = this.dealDatasets
      .map((deal: any) => Date.parse(deal.date))
      .filter((timestamp) => !isNaN(timestamp));
    if (timestamps.length > 0) {
      const firstDate = Math.min(...timestamps);
      const lastDate = Math.max(...timestamps);
      this.dealDateRangeDays = Math.round((lastDate - firstDate) / (1000 * 60 * 60 * 24)) + 1;
    }

    if (totalValue > 0) {
      this.deals = [
        {
          series: this.dealDatasets.map((deal: any) => {
            return {
              name: deal.date,
              value: deal.value,
              output: deal.value,
            };
          }),
          name: 'Deals',
        },
      ];

      if (this.plan.goal > 0) {
        this.planGoal = [
          {
            goal:
              this.plan.type === 'CallsPlan'
                ? this.plan.goal
                : formatCurrency(this.plan.goal, this.currencyLocale, this.currencySymbol),
            name: 'Deals',
            result:
              this.plan.type === 'CallsPlan'
                ? totalValue
                : formatCurrency(totalValue, this.currencyLocale, this.currencySymbol),
            value: ((totalValue / this.plan.goal) * 100).toPrecision(4),
          },
        ];
        const difference = Math.abs(totalValue - this.plan.goal);
        this.planGoalAbove = totalValue >= this.plan.goal;
        this.planGoalDifference =
          this.plan.type === 'CallsPlan'
            ? difference.toString()
            : formatCurrency(difference, this.currencyLocale, this.currencySymbol);
      }
    }
  }

  calendarRunning(calendar: Calendar) {
    if (calendar === undefined) {
      this.calendarClosesToday = false;
      return false;
    }

    const endDate = new Date(calendar.endsAt);
    const today = new Date();
    const endDay = new Date(Date.UTC(endDate.getUTCFullYear(), endDate.getUTCMonth(), endDate.getUTCDate()));
    const todayDay = new Date(Date.UTC(today.getFullYear(), today.getMonth(), today.getDate()));

    const differenceDateDays = (endDay.getTime() - todayDay.getTime()) / (1000 * 60 * 60 * 24);

    if (differenceDateDays > 0) {
      this.daysUntilCalendarCloses = String(differenceDateDays);
      this.calendarClosesToday = false;
      return true;
    } else if (differenceDateDays === 0) {
      this.calendarClosesToday = true;
      return false;
    } else {
      this.calendarClosesToday = false;
      return false;
    }
  }

  percentageApprovedStatements(totalAcceptedStatements: number, totalStatements: number) {
    if (totalAcceptedStatements > 0 && totalStatements > 0) {
      return ((totalAcceptedStatements / totalStatements) * 100).toFixed(2);
    }
  }

  percentageAboveAverage(money: number, averageMoney: number) {
    if (money > 0 && averageMoney > 0 && money > averageMoney) {
      const moneyDifference = money - averageMoney;
      const baseDivision = moneyDifference / averageMoney;
      return (baseDivision * 100).toFixed(2);
    }
  }

  percentageBelowAverage(money: number, averageMoney: number) {
    if (money > 0 && averageMoney > 0 && money < averageMoney) {
      const moneyDifference = averageMoney - money;
      const baseDivision = moneyDifference / money;
      return (baseDivision * 100).toFixed(2);
    }
  }

  getUserAggregatedUserCommissionDatasets() {
    const variables: Record<string, any> = {};

    if (this.planId !== undefined && this.planId !== null) {
      variables.planId = this.planId;
    }

    if (this.periodId !== undefined && this.periodId !== null) {
      variables.periodId = this.periodId;
    }

    if (this.userSort !== undefined && this.userSort !== null) {
      variables.sort = this.userSort;
    }

    if (this.userId !== undefined && this.userId !== null) {
      variables.userId = this.userId;
    }

    const userAggregatedUserCommissionDatasetsQuery = `query UserAggregatedUserCommissionDatasets($planId: ID, $periodId: ID, $sort: String, $userId: ID) {
      userAggregatedUserCommissionDatasets(
        planId: $planId
        periodId: $periodId
        sort: $sort
        userId: $userId
      ) {
        nodes {
          money
          planStatement {
            acceptment {
              id
            }
          }
          statement {
            acceptment {
              id
            }
          }
          points
          user {
            id
            name
            profile {
              id
            }
            seat {
              parent {
                user {
                  id
                  name
                  profile {
                    id
                  }
                }
              }
              type
            }
          }
        }
      }
    }`;

    this.userAggregatedUserCommissionDatasetsService
      .query('userAggregatedUserCommissionDatasets', userAggregatedUserCommissionDatasetsQuery, variables)
      .valueChanges.subscribe({
        next: (response: any) => {
          if (!response?.data || Object.keys(response.data).length === 0) {
            return;
          }

          if (response.data.userAggregatedUserCommissionDatasets.nodes.length > 0) {
            this.userAggregatedUserCommissionDatasets = response.data.userAggregatedUserCommissionDatasets.nodes;
            this.totalUserAggregatedUserCommissionDatasets = this.userAggregatedUserCommissionDatasets.length;
            this.totalMoneyUserAggregatedUserCommissionDatasets = this.sumUserCommissionDatasetsMoney(
              this.userAggregatedUserCommissionDatasets,
            );

            if (this.totalUserAggregatedUserCommissionDatasets) {
              this.averageMoneyUser =
                this.totalMoneyUserAggregatedUserCommissionDatasets / this.totalUserAggregatedUserCommissionDatasets;
              this.userAggregatedUserCommissionDatasetsAboveAverage = this.countUsersAboveAverage(
                this.userAggregatedUserCommissionDatasets,
                this.averageMoneyUser,
              );
              this.userAggregatedUserCommissionDatasetsBelowAverage = this.countUsersBelowAverage(
                this.userAggregatedUserCommissionDatasets,
                this.averageMoneyUser,
              );
            }

            this.userAggregatedUserCommissionDatasets = this.userAggregatedUserCommissionDatasets.map(
              (userCommissionDataset: UserCommissionDataset, index: number) => ({
                ...userCommissionDataset,
                ranking: index + 1,
                averageMoneyUser: this.averageMoneyUser,
                sort: this.userSort,
              }),
            );

            if (
              this.userAggregatedUserCommissionDatasets.length == 1 &&
              (this.currentUserSeat == 'SalesRepresentative' || this.userId !== undefined)
            ) {
              this.averageMoneyUser = this.userAggregatedUserCommissionDatasets[0].averageMoneyUser;
              this.selectedUserMoney = this.userAggregatedUserCommissionDatasets[0].money;
              this.selectedUserPlanStatement = this.userAggregatedUserCommissionDatasets[0].planStatement;
              this.selectedUserStatement = this.userAggregatedUserCommissionDatasets[0].statement;
              this.selectedUserRanking = this.userAggregatedUserCommissionDatasets[0].ranking;
              this.selectedUser = new User(this.userAggregatedUserCommissionDatasets[0].user);
              this.user = new User(this.userAggregatedUserCommissionDatasets[0].user);
              this.userId = this.userAggregatedUserCommissionDatasets[0]?.user?.id?.toString();
            }
          } else {
            this.userAggregatedUserCommissionDatasets = undefined;
          }
        },
      });
  }

  sumUserCommissionDatasetsMoney(userCommissionDatasets: UserCommissionDataset[]) {
    return userCommissionDatasets.reduce(
      (accumulator, userCommissionDatasets) => (accumulator + userCommissionDatasets.money) | 0,
      0,
    );
  }

  countUsersAboveAverage(userCommissionDatasets: UserCommissionDataset[], averageMoneyUser: number) {
    return userCommissionDatasets.filter(
      (userCommissionDataset: UserCommissionDataset) =>
        userCommissionDataset.money !== null &&
        userCommissionDataset.money !== undefined &&
        userCommissionDataset.money > averageMoneyUser,
    ).length;
  }

  countUsersBelowAverage(userCommissionDatasets: UserCommissionDataset[], averageMoneyUser: number) {
    return userCommissionDatasets.filter(
      (userCommissionDataset: UserCommissionDataset) =>
        userCommissionDataset.money !== null &&
        userCommissionDataset.money !== undefined &&
        userCommissionDataset.money < averageMoneyUser,
    ).length;
  }

  selectSort(event: Event): void {
    const target = event.target as HTMLSelectElement;
    this.averageMoneyUser = undefined;
    this.selectedUser = undefined;
    this.selectedUserMoney = undefined;
    this.selectedUserPlanStatement = undefined;
    this.selectedUserRanking = undefined;
    this.selectedUserStatement = undefined;
    this.user = undefined;
    this.userId = undefined;
    this.userSort = target.value;
    this.getUserCommissionDatasets();
    this.getUserAggregatedUserCommissionDatasets();
  }

  getIndicatorDatasets() {
    const variables: Record<string, any> = {};

    if (this.period.endsAt) {
      variables.endsAt = this.period.endsAt;
    }

    if (this.period.startsAt) {
      variables.startsAt = this.period.startsAt;
    }

    if (this.userId) {
      variables.userId = this.userId;
    }

    if (this.planId) {
      variables.planId = this.planId;
    }

    if (this.variableIds) {
      variables.variableIds = this.variableIds;
    }

    const indicatorDatasetQuery = `query IndicatorDatasets($endsAt: String!, $startsAt: String!, $userId: ID, $planId: ID, $variableIds: [ID!]) {
      indicatorDatasets(
        endsAt: $endsAt
        startsAt: $startsAt
        userId: $userId
        planId: $planId
        variableIds: $variableIds
      ) {
        nodes {
          date
          format
          output
          variableId
        }
      }
    }`;

    this.indicatorDatasetService
      .query('indicatorDataset', indicatorDatasetQuery, variables)
      .valueChanges.subscribe((response: any) => {
        if (!response?.data || Object.keys(response.data).length === 0) {
          return;
        }

        this.indicatorDatasets = response.data.indicatorDatasets.nodes;
        this.processLineCharts();
      });
  }

  processLineCharts() {
    this.lineCharts = this.variables
      .map((variable: Variable) => {
        const indicatorDatasets = this.indicatorDatasets.filter((indicatorDataset: IndicatorDataset) => {
          return indicatorDataset.variableId.toString() === variable.id.toString();
        });

        if (indicatorDatasets.length === 0) {
          return {};
        }

        return {
          name: variable.name,
          dataType: variable.dataType,
          series: indicatorDatasets.map((indicatorDataset: IndicatorDataset) => {
            return {
              name: indicatorDataset.date,
              value: parseFloat(indicatorDataset.format.toString()).toFixed(2),
              output: indicatorDataset.output,
              dataType: variable.dataType,
            };
          }),
        };
      })
      .reduce((prevValue: any, element: any) => {
        prevValue[element.name] = (prevValue[element.name] || []).concat(element);
        return prevValue;
      }, Object.create(null));
  }

  getVariables() {
    const variables: Record<string, any> = {
      type: 'IndicatorVariable',
      planId: this.planId,
    };

    const variableShowQuery = `query Variables($type: String, $planId: ID) {
      variables (
        type: $type
        planId: $planId
      ) {
        nodes {
          id
          name
          dataType
          metric {
            id
          }
        }
      }
    }`;

    this.variableService.query('variable', variableShowQuery, variables).valueChanges.subscribe((response: any) => {
      if (!response?.data || Object.keys(response.data).length === 0) {
        return;
      }

      this.variables = response.data.variables.nodes;
      this.variableIds = this.variables.map((variable: Variable) => variable.id);
      this.getGoalDatasets();
      this.getIndicatorDatasets();
    });
  }

  getPeriod() {
    const variables: Record<string, any> = {
      id: this.periodId,
    };

    const periodQuery = `query Periods($id: ID) {
      periods(
        id: $id
      ) {
        nodes {
          endsAt
          startsAt
        }
      }
    }`;

    this.periodService.query('period', periodQuery, variables).valueChanges.subscribe((response: any) => {
      if (!response?.data || Object.keys(response.data).length === 0) {
        return;
      }

      this.period = response.data.periods.nodes[0];
      this.getVariables();
    });
  }

  getCalendar() {
    const variables: Record<string, any> = {
      id: this.calendarId,
    };

    const calendarQuery = `query Calendars($id: ID) {
      calendars(
        id: $id
      ) {
        nodes {
          endsAt
          startsAt
        }
      }
    }`;

    this.calendarService.query('calendar', calendarQuery, variables).valueChanges.subscribe((response: any) => {
      if (!response?.data || Object.keys(response.data).length === 0) {
        return;
      }

      this.period = new Period(response.data.calendars.nodes[0]);
      this.getVariables();
    });
  }

  filterGoalDataset(variableId: string): GoalDataset {
    return this.goalDatasets.filter(
      (goalDataset: GoalDataset) => goalDataset.variableId.toString() === variableId.toString(),
    )[0];
  }

  getTemporaryProfiles() {
    this.loadingProfiles = true;

    const profileIds = this.getProfileIds();

    if (profileIds.size === 0) {
      this.loadingProfiles = false;
      return;
    }

    const requests: Record<string, Observable<any>> = {};

    profileIds.forEach((id) => {
      requests[id] = this.temporaryProfileService.get(id).valueChanges.pipe(
        filter((result: any) => !result.loading),
        take(1),
      );
    });

    forkJoin(requests).subscribe((results: Record<string, any>) => {
      this.setProfiles(results);
      this.changeDetectorRef.detectChanges();
      this.loadingProfiles = false;
    });
  }

  private getProfileIds(): Set<string | number> {
    const ids = new Set<string | number>();

    if (this.plan?.owner?.profile?.id) {
      ids.add(this.plan.owner.profile.id);
    }

    this.plan?.responsible?.forEach((responsible: any) => {
      if (responsible.profile?.id) {
        ids.add(responsible.profile.id);
      }
    });

    this.userAggregatedUserCommissionDatasets?.forEach((dataset: any) => {
      if (dataset.user?.profile?.id) {
        ids.add(dataset.user.profile.id);
      }

      if (dataset.user?.seat?.parent?.user?.profile?.id) {
        ids.add(dataset.user.seat.parent.user.profile.id);
      }
    });

    return ids;
  }

  private setProfiles(results: Record<string, any>) {
    if (this.plan?.owner?.profile?.id) {
      this.plan.owner.profile.url = results[this.plan.owner.profile.id]?.data?.temporaryProfile?.url;
    }

    this.plan?.responsible?.forEach((responsible: any) => {
      if (responsible.profile?.id) {
        responsible.profile.url = results[responsible.profile.id]?.data?.temporaryProfile?.url;
      }
    });

    this.userAggregatedUserCommissionDatasets?.forEach((dataset: any) => {
      if (dataset.user?.profile?.id) {
        dataset.user.profile.url = results[dataset.user.profile.id]?.data?.temporaryProfile?.url;
      }

      if (dataset.user?.seat?.parent?.user?.profile?.id) {
        dataset.user.seat.parent.user.profile.url =
          results[dataset.user.seat.parent.user.profile.id]?.data?.temporaryProfile?.url;
      }
    });
  }
}
