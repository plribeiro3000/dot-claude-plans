// Raw source capture. Fetched verbatim via raw.githubusercontent.com (curl) for citation accuracy.
// Source: https://raw.githubusercontent.com/renovatebot/renovate/main/lib/util/package-rules/current-value.ts
// Fetched: 2026-08-14
// This is the implementation of the `matchCurrentValue` packageRules matcher.

import { isUndefined } from '@sindresorhus/is';
import type {
  PackageRule,
  PackageRuleInputConfig,
} from '../../config/types.ts';
import { getRegexOrGlobPredicate } from '../string-match.ts';
import { Matcher } from './base.ts';

export class CurrentValueMatcher extends Matcher {
  override matches(
    { currentValue }: PackageRuleInputConfig,
    { matchCurrentValue }: PackageRule,
  ): boolean | null {
    if (isUndefined(matchCurrentValue)) {
      return null;
    }
    const matchCurrentValuePred = getRegexOrGlobPredicate(matchCurrentValue);

    if (!currentValue) {
      return false;
    }

    return matchCurrentValuePred(currentValue);
  }
}
