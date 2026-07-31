// Auxiliary file for SPIKE.md — full verbatim copy for reference.
// Source: ~/Projects/4Shark/app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.ts
// Repo commit at capture time: f1920fb6bed46c477028113d90df1994ad48f278
// Relevant to demand 4 (collapse/expand + signature lock) and demand 7 (formula visibility).
// Note: `readyToSign()` (allExpanded gate) and the auto-expand-on-load logic in
// ngOnInit already implement the signature lock shipped in CHANGELOG 1.281.0
// (2026-07-28) — see roadmap-barigui_changelog_1.md.

import { ActivatedRoute } from '@angular/router';
import { Component, OnInit } from '@angular/core';
import { NgbModal } from '@ng-bootstrap/ng-bootstrap';

import { GoalPlan } from '@app/goal-plan/goal-plan.model';
import { GoalPlanService } from '@app/goal-plan/goal-plan.service';
import { Incentive } from '@app/incentive/incentive.model';
import { PlanStatement } from '@app/plan-statement/plan-statement.model';
import { PlanStatementService } from '../plan-statement.service';
import { PlanStatementAcceptComponent } from '@app/plan-statement/plan-statement-accept/plan-statement-accept.component';
import { TemporarySignatureService } from '@app/signature/temporary-signature.service';
import { TranslateService } from '@ngx-translate/core';

@Component({
  standalone: false,
  selector: 'app-plan-statement-show',
  templateUrl: './plan-statement-show.component.html',
  styleUrls: ['./plan-statement-show.component.scss'],
})
export class PlanStatementShowComponent implements OnInit {
  private shouldExpandOnLoad = false;
  dealIncentives: Incentive[];
  goalPlans: GoalPlan[] = [new GoalPlan({})];
  indicatorIncentives: Incentive[];
  limiterIncentives: Incentive[];
  loading: boolean;
  planStatement: PlanStatement;
  planStatementId: string;
  rankifierIncentives: Incentive[];
  redemptionIncentives: Incentive[];
  signature: { id: number; url: string } | null = null;

  constructor(
    private goalPlanService: GoalPlanService,
    private planStatementService: PlanStatementService,
    private route: ActivatedRoute,
    private temporarySignatureService: TemporarySignatureService,
    private modalService: NgbModal,
    public translateService: TranslateService,
  ) {}

  ngOnInit() {
    this.route.queryParams.subscribe((queryParams: any) => {
      this.shouldExpandOnLoad = queryParams.expand === 'true';
    });

    this.route.params.subscribe((params: any) => {
      this.planStatementId = params.planStatementId;
      this.getPlanStatement();
    });
  }

  getPlanStatement() {
    this.loading = true;
    const variables: Record<string, any> = { id: this.planStatementId };
    this.planStatementService
      .query(
        'planStatement',
        `query PlanStatementShow($id: ID) {
          planStatements(id: $id) {
            nodes {
              acceptment {
                acceptmentReason {
                  description
                  name
                }
                createdAt
                from
                signature {
                  id
                }
                user {
                  id
                  name
                }
              }
              actions
              createdAt
              id
              plan {
                id
                calendar {
                  endsAt
                  frequency
                  reference
                  startsAt
                }
                disabledAt
                goal
                groupId
                incentives {
                  client {
                    name
                  }
                  name
                  reference
                  product {
                    name
                  }
                  rankifier {
                    name
                    rankifierVariables {
                      cap
                      comparator
                      goal
                      minimum
                      variable {
                        name
                        dataType
                      }
                      weight
                    }
                    type
                  }
                  rules {
                    description
                    value
                  }
                  type
                }
                name
                policyDocument
              }
              status
              user {
                email
                id
                name
                department
              }
              userFieldSnapshots {
                key
                value
              }
            }
          }
        }`,
        variables,
      )
      .valueChanges.subscribe((response: any) => {
        if (response.loading) {
          return;
        }

        if (!response?.data || Object.keys(response.data).length === 0) {
          this.loading = false;
          return;
        }

        this.planStatement = response.data.planStatements.nodes[0];

        const incentives = response.data.planStatements.nodes[0].plan.incentives.reduce(
          (prevValue: any, element: any) => {
            prevValue[element.type] = (prevValue[element.type] || []).concat(element);
            return prevValue;
          },
          Object.create(null),
        );

        const goalPlanVariables: Record<string, any> = {
          planId: this.planStatement.plan.id,
          userId: this.planStatement.user.id,
          groupId: this.planStatement.plan.groupId,
        };

        this.goalPlanService
          .query(
            'goalPlan',
            `query UserPlanGoals($planId: ID, $userId: ID, $groupId: ID) {
              userPlanGoals(planId: $planId, userId: $userId, groupId: $groupId) {
                pageInfo {
                  endCursor
                }
                nodes {
                  value
                  goal {
                    endsAt
                    startsAt
                    type
                    variable {
                      name
                    }
                  }
                }
              }
            }`,
            goalPlanVariables,
          )
          .valueChanges.subscribe((goalPlansResponse: any) => {
            if (!response?.data || Object.keys(response.data).length === 0) {
              return;
            }

            this.goalPlans = goalPlansResponse.data?.userPlanGoals?.nodes ?? [];
          });

        if (incentives.DealIncentive) {
          this.dealIncentives = incentives.DealIncentive;
        }

        if (incentives.LimiterIncentive) {
          this.limiterIncentives = incentives.LimiterIncentive;
        }

        if (incentives.IndicatorIncentive) {
          this.indicatorIncentives = incentives.IndicatorIncentive;
        }

        if (incentives.RankingIncentive) {
          this.rankifierIncentives = incentives.RankingIncentive;
        }

        if (incentives.RedemptionIncentive) {
          this.redemptionIncentives = incentives.RedemptionIncentive;
        }

        // NOTE (demand 4): whenever the plan statement can be accepted, EVERY
        // panel auto-expands on load. Barigui wants collapsed-by-default; this
        // is the exact behavior that contradicts that ask.
        if (this.shouldExpandOnLoad || (this.planStatement.actions && this.planStatement.actions.includes('accept'))) {
          this.expandPanels(true);
        }

        this.loading = false;
        this.getSignature();
      });
  }

  getSignature() {
    const signatureId = this.planStatement?.acceptment?.signature?.id;

    if (!signatureId) {
      return;
    }

    this.temporarySignatureService.get(signatureId).valueChanges.subscribe((response: any) => {
      if (!response?.data?.temporarySignature) {
        return;
      }

      this.signature = response.data.temporarySignature;
    });
  }

  panels(): Incentive[] {
    const groups = [
      this.dealIncentives,
      this.indicatorIncentives,
      this.limiterIncentives,
      this.rankifierIncentives,
      this.redemptionIncentives,
    ];
    const expandablePanels: Incentive[] = [];

    groups.forEach((group: Incentive[]) => {
      if (group) {
        expandablePanels.push(...group);
      }
    });

    return expandablePanels;
  }

  allExpanded() {
    return this.panels().every((panel: any) => panel.expanded);
  }

  expandPanels(expanded: boolean) {
    this.panels().forEach((panel: any) => {
      panel.expanded = expanded;
    });
  }

  togglePanels() {
    this.expandPanels(!this.allExpanded());
  }

  // NOTE (demand 4): this is the signature-lock gate already shipped —
  // the Accept button is [disabled]="!readyToSign()" in the template.
  readyToSign() {
    return this.allExpanded() && !this.loading;
  }

  forcedAcceptance() {
    const planStatement: any = this.planStatement;

    if (!planStatement || !planStatement.acceptment) {
      return false;
    }

    return planStatement.acceptment.user.id !== planStatement.user.id;
  }

  displayMinimum(rankingIncentive: any) {
    return rankingIncentive?.rankifier.type === 'WeightRankifier';
  }

  displayCap(rankingIncentive: any) {
    return rankingIncentive.rankifier.type === 'GoalReachRankifier';
  }

  print() {
    window.print();
  }

  openSignatureDialog() {
    const modalRef = this.modalService.open(PlanStatementAcceptComponent, {
      size: 'lg',
      centered: true,
      backdrop: 'static',
      keyboard: false,
    });

    modalRef.componentInstance.planStatementId = this.planStatementId;
  }
}
