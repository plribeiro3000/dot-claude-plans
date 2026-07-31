# Auxiliary file — verbatim excerpt of app/app/models/reward.rb:45-109
#
# Kept as an in-repo precedent for pessimistic locking around a read-compute-write sequence on a
# shared numeric column under concurrent workers ("financial operations" — the same shape BE-6
# needs for aggregated_modifiers.value). Copied verbatim, comments included, because the precedent
# IS the comments explaining why the lock is there.

# Computes the available budget directly in the database, without using application memory or the Rails query cache.
# COALESCE ensures the method always returns a numeric value (0 if NULL) for type safety in financial operations.
def available_budget
  self.class.connection.uncached do
    self.class.unscoped.where(id: id).pick(Arel.sql('COALESCE(budget, 0) - COALESCE(released_budget, 0)'))
  end
end

# Uses pessimistic locking (lock!) to prevent race conditions in financial operations.
#
# Operation order matters:
# 1. lock! (ActiveRecord) - Acquires exclusive row lock (FOR UPDATE), blocks other transactions until commit/rollback
# 2. increment! (ActiveRecord) - Updates database directly (budget += amount) but doesn't refresh in-memory object
# 3. reload (ActiveRecord) - Synchronizes in-memory object state with current database values
# 4. replenish! (State machine) - Transitions status from :exhausted to :available if budget is now positive
def increment_budget(amount)
  return false unless amount.is_a?(Numeric)
  return false if amount.zero? || amount.negative?

  transaction do
    lock!
    increment!(:budget, amount)
    reload
    replenish! if exhausted? && available_budget.positive?
    true
  end
rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved
  errors.add(:base, :invalid)
  false
end

# Uses pessimistic locking to ensure consistent budget reads during concurrent operations.
# The lock prevents other transactions from modifying budget/released_budget while we check,
# avoiding TOCTOU (time-of-check-time-of-use) race conditions in financial validations.
def available_budget?(amount)
  return false if amount.nil?
  return false unless amount.is_a?(Numeric)
  return false if amount.zero? || amount.negative?

  transaction do
    lock!
    available_budget >= amount
  end
end

# Releases budget for a payment and transitions it to final state atomically.
#
# Operation order:
# 1. Locks campaign (budget holder)
# 2. Finds and locks payment (state holder)
# 3. Validates sufficient budget
# 4. Consumes budget and releases payment in single transaction
#
# Returns true if payment was released successfully, false otherwise.
def release_payment(payment_id)
  return false if payment_id.nil?

  transaction do
    lock!
    payment = payments.lock.find(payment_id)

    return false unless payment.releasing?
    return false if payment.value.nil? || payment.value.zero? || payment.value.negative?
    # (truncated — remainder of method not relevant to the locking pattern being cited)
  end
end
