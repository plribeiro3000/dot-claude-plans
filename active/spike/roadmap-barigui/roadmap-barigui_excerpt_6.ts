// Auxiliary file for SPIKE.md — partial verbatim excerpt for reference (NOT the
// full file — statement-show.component.ts is 1000+ lines).
// Source: ~/Projects/4Shark/app-webclient/src/app/statement/statement-show/statement-show.component.ts
// Repo commit at capture time: f1920fb6bed46c477028113d90df1994ad48f278
// Relevant to demand 4 — a SECOND, independent implementation of the same
// collapse/expand + signature-lock mechanism found in plan-statement-show
// (roadmap-barigui_excerpt_4.ts), for the "statement" (deal/commission-based)
// acceptance flow rather than the "plan statement" flow. Both must change
// together for demand 4 to be complete, and both currently auto-expand.

// --- field declaration (line 44) ---
  reviewing = false;

// --- ngOnInit route.queryParams subscription (lines 124-126) ---
    this.route.queryParams.subscribe((queryParams: any) => {
      this.reviewing = queryParams.expand === 'true';
    });

// --- getStatement() response handler (lines 215-236) ---
    this.statementService.query('statement', query, variables).valueChanges.subscribe((response: any) => {
      if (!response?.data || Object.keys(response.data).length === 0) {
        return;
      }

      this.statement = response.data.statements.nodes[0];
      this.loadingStatement = false;

      // NOTE (demand 4): identical auto-expand-on-load trigger as
      // plan-statement-show.component.ts:217 — "reviewing = true" makes
      // isExpanded() below return true for every panel with no individually
      // set .expanded, i.e. every panel by default.
      if (this.statement.actions && this.statement.actions.includes('accept')) {
        this.reviewing = true;
      }

      this.getGoals();
      this.getCollaborativeDealCommissionings();
      this.getDealCommissionings();
      this.getAccumulatedDeals();
      this.getIndicatorCommissionings();
      this.getRankifierCommissionings();
      this.getRankings();
      this.getLimiterCommissionings();
      this.getRedemptionCommissionings();
      this.getSignature();
    });

// --- expand/collapse + signature-lock machinery (lines 945-1039) ---

  isExpanded(panel: any) {
    if (panel.expanded === undefined) {
      return this.reviewing;
    }

    return panel.expanded;
  }

  panels(): any[] {
    const groups = [
      this.dealCommissionings,
      this.indicatorCommissionings,
      this.rankifierCommissionings,
      this.limiterCommissionings,
      this.redemptionCommissionings,
    ];
    const expandablePanels: any[] = [];

    groups.forEach((group: any[]) => {
      if (group) {
        expandablePanels.push(...group);
      }
    });

    if (this.rankingIds && this.rankings) {
      this.rankingIds.forEach((rankingId: any) => {
        if (this.rankings[rankingId] && this.rankings[rankingId][0]) {
          expandablePanels.push(this.rankings[rankingId][0]);
        }
      });
    }

    return expandablePanels;
  }

  paginationDrained() {
    return [
      this.hasMoreDealCommissionings(),
      this.hasMoreAccumulatedDeals(),
      this.hasMoreIndicatorCommissionings(),
      this.hasMoreLimiterCommissionings(),
      this.hasMoreRankifierCommissionings(),
      this.hasMoreRedemptionCommissionings(),
    ].every((hasMore: boolean) => !hasMore);
  }

  // NOTE: allExpanded() here ALSO requires pagination to be fully drained
  // (every "load more" button exhausted) — a stricter gate than
  // plan-statement-show's allExpanded(), which has no pagination to drain.
  allExpanded() {
    return this.panels().every((panel: any) => this.isExpanded(panel)) && this.paginationDrained();
  }

  expandPanels(expanded: boolean) {
    this.panels().forEach((panel: any) => {
      panel.expanded = expanded;
    });

    this.reviewing = expanded;

    if (expanded) {
      this.loadAllPages();
    }
  }

  togglePanels() {
    this.expandPanels(!this.reviewing);
  }

  loadAllPages() {
    if (this.dealCommissioningsLastPageLength == 9) {
      this.getDealCommissionings();
    }

    if (this.accumulatedDealsLastPageLength == 9) {
      this.getAccumulatedDeals();
    }

    if (this.indicatorCommissioningsLastPageLength == 9) {
      this.getIndicatorCommissionings();
    }

    if (this.limiterCommissioningsLastPageLength == 9) {
      this.getLimiterCommissionings();
    }

    if (this.rankifierCommissioningsLastPageLength == 9) {
      this.getRankifierCommissionings();
    }

    if (this.redemptionCommissioningsLastPageLength == 9) {
      this.getRedemptionCommissionings();
    }
  }

  readyToSign() {
    return this.allExpanded() && !this.loading;
  }
