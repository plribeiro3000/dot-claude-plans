<!-- Auxiliary file for SPIKE.md — verbatim excerpt (lines 1-140) for reference. -->
<!-- Source: ~/Projects/4Shark/app-webclient/CHANGELOG.md -->
<!-- Repo commit at capture time: f1920fb6bed46c477028113d90df1994ad48f278 -->
<!-- Relevant to demand 4 (signature lock already shipped 2026-07-28) and
     demand 6 (infinite scroll rollout dated 2026-07-06, "the week before" the
     2026-07-13 meeting, matching the demand's own claim). -->

# Change Log

All notable changes to this project will be documented in this file.
This project adheres to [Semantic Versioning](http://semver.org/).
See [Keep a Changelog](http://keepachangelog.com/en/1.0.0/) and [Angular Commit Guidelines](https://github.com/angular/angular.js/blob/master/CONTRIBUTING.md#commit)
for guidelines followed by this project.

To keep this file readable, only the current year's releases and hotfixes are kept here.
Entries from previous years are archived in the [changelogs](changelogs) folder.

## [Unreleased]

### Fixed

- Validation limits on the spreadsheet import report messages

## [1.282.0] - 2026-07-30

### Added

- Bulk user update by spreadsheet
- Specific messages for rule formula syntax problems

### Fixed

- Rule error messages on the incentive spreadsheet import report
- User and collaborative deal error messages on the spreadsheet import report

## [1.281.3] - 2026-07-29

### Fixed

- Chart tooltips

## [1.281.2] - 2026-07-29

### Fixed

- Indicator dashboard chart
- Deal dataset dashboard chart

## [1.281.1] - 2026-07-29

### Fixed

- Plan selection on the commission, statement, campaign and event screens

## [1.281.0] - 2026-07-28

### Added

- Full-content view for the rule declaration
- Full-content view for the result declaration
- Full content review required before signing a declaration
- Guidance when a declaration must be fully expanded to sign
- Document error report download

### Changed

- Plan listing order

### Fixed

- Import error messages for document uploads
- Shared and override filter defaults in the plans list
- Forced-acceptance details on the rule declaration
- Result declaration commission lists limited to the first page
- Panel collapse while reviewing a declaration
- Integration report opening the wrong page for payroll integrations
- Deal dataset dashboard chart

## [1.280.1] - 2026-07-28

### Fixed

- Rule removal on incentive update not persisting after deletion

## [1.280.0] - 2026-07-10

### Added

- Company retention jurisdiction country
- Group and collaborator count columns in commission and partial commission listings

## [1.279.0] - 2026-07-10

### Added

- User history Excel regeneration button

## [1.278.0] - 2026-07-08

### Added

- Client-specific translation overrides
- Month and year selection for statement audit generation
- User history Excel regeneration

### Fixed

- Missing import error translations for incentive documents (transactional, indicator, limiter, ranking, and redemption)

## [1.277.0] - 2026-07-07

### Added

- User history Excel download

## [1.276.0] - 2026-07-07

### Changed

- Bulk user actions menu

## [1.275.0] - 2026-07-06

### Added

- Bulk hierarchy change

### Changed

- Calendar dashboard plan card labels
- Infinite scroll on acceptment document, acceptment reason, calendar, calendar audit, campaign, client, client document, and collaborative deal listings
- Infinite scroll on collaborative deal document, commission, commission creation batch, commission indicator audit, commission processing event, commission release event, commission report creation batch, and company listings
- Infinite scroll on deal, deal document, deal incentive, goal document, and goal listings
- Infinite scroll on group audit, group document, group, groupification document, incentive document, indicator document, indicator incentives, and indicator listings
- Infinite scroll on limiter incentives, metric, monthly usage, monthly usage responsibility, partial commission, password document, payment integration, and payment listings
- Infinite scroll on payment type, plan acceptment, plan document, plan goal audit, plan participation approval batch, plan participation, plan, and plan rollback listings
- Infinite scroll on plan statement audit, plan statement, product document, product, rankifier incentives, rankifier, redemption incentives, and responsible audit listings
- Infinite scroll on reward fund, reward payment, reward, security event audit, security event, statement audit, statement, and status listings
- Infinite scroll on subsidiary, voucher, upload, user activity document, user audit, user document, user history, and user identifier audit listings
- Infinite scroll on user identifier document, user identifier, user payment, user, variable audit, variable document, and variable listings
- Plan dashboard selected user name for admins and managers

## [1.274.0] - 2026-06-30

### Added

- Bulk group creation
