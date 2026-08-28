# Revert of the 2026-08-18 real integration test on payment 7559 (company 97, Maqnelson).
#
# WHEN TO RUN: only AFTER Maqnelson validates the 10 sent values on their Nexus.
# WHERE: any Rails console with DB access (this is DB-only, no network, no VPN needed).
#
# What the perform wrote and this reverts (the whole footprint):
#   - payment.status         : final -> ... -> integrated        => back to 'final' (raw write; no
#                                                                    state-machine event integrated->final,
#                                                                    and Payment has no transition callback
#                                                                    at payment.rb:54-99)
#   - user_payments status   : 10 -> success, 4 -> skipped        => all 14 back to 'pending'
#   - reference_month         : temporarily set to 2026-08-01      => back to nil (the payment had none)
#   - PayrollRequest rows      : 1 success (execution)             => deleted
#   - PayrollAuthenticationRequest rows : success + the earlier    => deleted
#                                console-failure 'error' row
#
# Expected DEPOIS: status=final, reference_month=nil, PayrollRequest=0,
#                  PayrollAuthenticationRequest=0, user_payment pending: 14

payment_id = 7559
payment = Payment.find(payment_id)

puts "ANTES:"
puts "  status: #{payment.status}"
puts "  reference_month: #{payment.reference_month.inspect}"
puts "  PayrollRequest: #{PayrollRequest.where(payment_id: payment_id).count}"
puts "  PayrollAuthenticationRequest: #{PayrollAuthenticationRequest.where(payment_id: payment_id).count}"
payment.user_payments.group(:integration_status).count.each { |integration_status, total| puts "  user_payment #{integration_status}: #{total}" }

# Delete the integration audit rows (both attempts). Pluck ids + destroy individually (Bulk Delete policy).
# PayrollRequest first (it references the authentication request).
PayrollRequest.where(payment_id: payment_id).ids.each { |request_id| PayrollRequest.find(request_id).destroy }
PayrollAuthenticationRequest.where(payment_id: payment_id).ids.each { |request_id| PayrollAuthenticationRequest.find(request_id).destroy }

# All 14 user_payments were 'pending' before the test.
payment.user_payments.update_all(integration_status: :pending)

# Raw column write: no state-machine event integrated -> final, and no transition callbacks to undo.
payment.update_columns(status: 'final', reference_month: nil)

payment.reload
puts "DEPOIS:"
puts "  status: #{payment.status}"
puts "  reference_month: #{payment.reference_month.inspect}"
puts "  PayrollRequest: #{PayrollRequest.where(payment_id: payment_id).count}"
puts "  PayrollAuthenticationRequest: #{PayrollAuthenticationRequest.where(payment_id: payment_id).count}"
payment.user_payments.group(:integration_status).count.each { |integration_status, total| puts "  user_payment #{integration_status}: #{total}" }
