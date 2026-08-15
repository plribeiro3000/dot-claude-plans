// Renovate source excerpts establishing the `matchCurrentValue: "*"` mechanism.
// Fetched verbatim via curl from raw.githubusercontent.com/renovatebot/renovate/main/, 2026-08-14.

// =====================================================================
// FILE: lib/util/package-rules/current-value.ts
// =====================================================================
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

// =====================================================================
// FILE: lib/util/string-match.ts (relevant excerpt)
// =====================================================================
export function getRegexOrGlobPredicate(pattern: string): StringMatchPredicate {
  const regExPredicate = getRegexPredicate(pattern);
  if (regExPredicate) {
    return regExPredicate;
  }

  const mm = minimatch(pattern, { dot: true, nocase: true });
  return (x: string): boolean => mm.match(x);
}

// =====================================================================
// FILE: lib/util/minimatch.ts (relevant excerpt — confirms plain npm `minimatch`
// package is used with no override that would change "*" glob semantics)
// =====================================================================
import type { MinimatchOptions } from 'minimatch';
import { Minimatch } from 'minimatch';

export function minimatch(
  pattern: string,
  options?: MinimatchOptions,
  useCache = true,
): Minimatch {
  const instance = new Minimatch(pattern, options);
  return instance;
}

// =====================================================================
// EMPIRICAL TEST — ran locally against the actual `minimatch` npm package
// (installed via `npm install minimatch --prefix /tmp/mm-test`, then
// `node -e "..."`), 2026-08-14, to confirm "*" matches realistic Gemfile
// constraint strings and does not match an empty/absent value:
//
//   new Minimatch('*', {dot:true, nocase:true}).match('~> 8.0')  => true
//   new Minimatch('*', {dot:true, nocase:true}).match('<3')      => true
//   new Minimatch('*', {dot:true, nocase:true}).match('1.4.0')   => true
//   new Minimatch('*', {dot:true, nocase:true}).match('>= 7.0')  => true
//   new Minimatch('*', {dot:true, nocase:true}).match('')        => false
//
// Combined with CurrentValueMatcher's `if (!currentValue) return false`
// short-circuit (which fires before the glob predicate ever runs, so an
// unconstrained gem's `undefined` currentValue never reaches the "*" test
// at all), this means `matchCurrentValue: "*"` is a working generic
// selector for "this gem carries ANY Gemfile version constraint" with no
// per-gem name enumeration required.
// =====================================================================
