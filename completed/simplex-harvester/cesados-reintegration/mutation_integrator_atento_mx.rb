# ---------------------------------------------------------------------------
# MUTATION - Atento MX reconciliation, integrator normalized base
# Paste into: bin/ecs run atento-mx   (Rails console)
# Runs inside Database.with_connection so the pooled adapter is used DIRECTLY
# (the Database wrapper's method_missing does NOT forward keyword args, which
# breaks execute_procedure(name:, params:)). Per target: re-resolves carnet ->
# fsk_users.id live and ONLY mutates on a single match to the pre-flight id.
# @mode='DEBUG' -> the INSERT into fsk_user_activity still happens (NOT a dry
# run); the SP also SELECTs the inserted row, logged as proof when returned.
# Success = the call did not raise. The integrator propagates to the app on its
# next run. Continue-on-error. Output @-separated for Excel.
# ---------------------------------------------------------------------------
targets = [
  { action: 'enable', app_user_id: 1003083, carnet: 15525, expected_id: 3474 },
  { action: 'enable', app_user_id: 995849, carnet: 43314, expected_id: 3227 },
  { action: 'enable', app_user_id: 991840, carnet: 46692, expected_id: 3295 },
  { action: 'enable', app_user_id: 1007807, carnet: 61678, expected_id: 9885 },
  { action: 'enable', app_user_id: 995745, carnet: 120751, expected_id: 1337 },
  { action: 'enable', app_user_id: 1024429, carnet: 126677, expected_id: 1028 },
  { action: 'enable', app_user_id: 990978, carnet: 139993, expected_id: 2944 },
  { action: 'enable', app_user_id: 1038830, carnet: 145062, expected_id: 9816 },
  { action: 'enable', app_user_id: 997015, carnet: 147139, expected_id: 1448 },
  { action: 'enable', app_user_id: 997895, carnet: 147892, expected_id: 1467 },
  { action: 'enable', app_user_id: 994558, carnet: 149296, expected_id: 1518 },
  { action: 'enable', app_user_id: 1038944, carnet: 150823, expected_id: 1575 },
  { action: 'enable', app_user_id: 1038986, carnet: 151882, expected_id: 9684 },
  { action: 'enable', app_user_id: 1039009, carnet: 152594, expected_id: 2807 },
  { action: 'enable', app_user_id: 995662, carnet: 154029, expected_id: 1699 },
  { action: 'enable', app_user_id: 1064121, carnet: 158107, expected_id: 1907 },
  { action: 'enable', app_user_id: 991846, carnet: 159377, expected_id: 1949 },
  { action: 'enable', app_user_id: 1039279, carnet: 161267, expected_id: 2037 },
  { action: 'enable', app_user_id: 990684, carnet: 161990, expected_id: 2072 },
  { action: 'enable', app_user_id: 994821, carnet: 162800, expected_id: 2103 },
  { action: 'enable', app_user_id: 1039324, carnet: 163330, expected_id: 2618 },
  { action: 'enable', app_user_id: 997908, carnet: 163617, expected_id: 2142 },
  { action: 'enable', app_user_id: 1039393, carnet: 164302, expected_id: 2647 },
  { action: 'enable', app_user_id: 991447, carnet: 165141, expected_id: 2218 },
  { action: 'enable', app_user_id: 996682, carnet: 165267, expected_id: 2223 },
  { action: 'enable', app_user_id: 991423, carnet: 165366, expected_id: 2239 },
  { action: 'enable', app_user_id: 995789, carnet: 166496, expected_id: 2311 },
  { action: 'enable', app_user_id: 1043149, carnet: 166557, expected_id: 2917 },
  { action: 'enable', app_user_id: 996325, carnet: 167467, expected_id: 2369 },
  { action: 'enable', app_user_id: 993822, carnet: 167712, expected_id: 2385 },
  { action: 'enable', app_user_id: 996590, carnet: 168649, expected_id: 2459 },
  { action: 'enable', app_user_id: 1039567, carnet: 168813, expected_id: 2972 },
  { action: 'enable', app_user_id: 991973, carnet: 170248, expected_id: 6143 },
  { action: 'enable', app_user_id: 1039683, carnet: 170504, expected_id: 3165 },
  { action: 'enable', app_user_id: 1039687, carnet: 170562, expected_id: 3166 },
  { action: 'enable', app_user_id: 1039739, carnet: 171030, expected_id: 3218 },
  { action: 'enable', app_user_id: 991369, carnet: 171101, expected_id: 3194 },
  { action: 'enable', app_user_id: 991910, carnet: 171118, expected_id: 3188 },
  { action: 'enable', app_user_id: 995812, carnet: 171142, expected_id: 3191 },
  { action: 'enable', app_user_id: 996644, carnet: 171340, expected_id: 9869 },
  { action: 'enable', app_user_id: 991695, carnet: 171442, expected_id: 3256 },
  { action: 'enable', app_user_id: 991701, carnet: 171445, expected_id: 3263 },
  { action: 'enable', app_user_id: 1024136, carnet: 171689, expected_id: 3287 },
  { action: 'enable', app_user_id: 991794, carnet: 171803, expected_id: 3297 },
  { action: 'enable', app_user_id: 1025218, carnet: 172093, expected_id: 9785 },
  { action: 'enable', app_user_id: 991528, carnet: 172104, expected_id: 3362 },
  { action: 'enable', app_user_id: 991680, carnet: 172129, expected_id: 3361 },
  { action: 'enable', app_user_id: 1002329, carnet: 172184, expected_id: 3406 },
  { action: 'enable', app_user_id: 1024268, carnet: 172425, expected_id: 9884 },
  { action: 'enable', app_user_id: 991267, carnet: 172429, expected_id: 9784 },
  { action: 'enable', app_user_id: 1039833, carnet: 172675, expected_id: 9686 },
  { action: 'enable', app_user_id: 1003075, carnet: 172857, expected_id: 3472 },
  { action: 'enable', app_user_id: 1017955, carnet: 172937, expected_id: 3484 },
  { action: 'enable', app_user_id: 994030, carnet: 173054, expected_id: 9779 },
  { action: 'enable', app_user_id: 996878, carnet: 173230, expected_id: 3522 },
  { action: 'enable', app_user_id: 1039871, carnet: 173390, expected_id: 3907 },
  { action: 'enable', app_user_id: 1022225, carnet: 173851, expected_id: 3601 },
  { action: 'enable', app_user_id: 1018039, carnet: 174031, expected_id: 3617 },
  { action: 'enable', app_user_id: 1018043, carnet: 174044, expected_id: 3610 },
  { action: 'enable', app_user_id: 1018057, carnet: 174075, expected_id: 3620 },
  { action: 'enable', app_user_id: 1024343, carnet: 174388, expected_id: 3654 },
  { action: 'enable', app_user_id: 1024347, carnet: 174410, expected_id: 3653 },
  { action: 'enable', app_user_id: 1039972, carnet: 174738, expected_id: 9770 },
  { action: 'enable', app_user_id: 1027533, carnet: 175162, expected_id: 3754 },
  { action: 'enable', app_user_id: 1020149, carnet: 175573, expected_id: 3812 },
  { action: 'enable', app_user_id: 1040183, carnet: 176316, expected_id: 9819 },
  { action: 'enable', app_user_id: 1032734, carnet: 176338, expected_id: 3921 },
  { action: 'enable', app_user_id: 1023677, carnet: 176344, expected_id: 3917 },
  { action: 'enable', app_user_id: 1040267, carnet: 176628, expected_id: 3951 },
  { action: 'enable', app_user_id: 1040281, carnet: 176642, expected_id: 3954 },
  { action: 'enable', app_user_id: 1040283, carnet: 176644, expected_id: 3955 },
  { action: 'enable', app_user_id: 1040342, carnet: 176754, expected_id: 3997 },
  { action: 'enable', app_user_id: 1040363, carnet: 176792, expected_id: 9886 },
  { action: 'enable', app_user_id: 1040466, carnet: 176962, expected_id: 4026 },
  { action: 'enable', app_user_id: 1022180, carnet: 177095, expected_id: 4035 },
  { action: 'enable', app_user_id: 1022117, carnet: 177147, expected_id: 4041 },
  { action: 'enable', app_user_id: 1040769, carnet: 177365, expected_id: 4063 },
  { action: 'enable', app_user_id: 1048589, carnet: 177602, expected_id: 9887 },
  { action: 'enable', app_user_id: 1048738, carnet: 177764, expected_id: 4120 },
  { action: 'enable', app_user_id: 1048741, carnet: 177767, expected_id: 4119 },
  { action: 'enable', app_user_id: 1048764, carnet: 177792, expected_id: 4128 },
  { action: 'enable', app_user_id: 1048997, carnet: 178032, expected_id: 4174 },
  { action: 'enable', app_user_id: 1049004, carnet: 178039, expected_id: 4177 },
  { action: 'enable', app_user_id: 1059235, carnet: 178181, expected_id: 9820 },
  { action: 'enable', app_user_id: 1059340, carnet: 178293, expected_id: 4221 },
  { action: 'enable', app_user_id: 1059489, carnet: 178451, expected_id: 4247 },
  { action: 'enable', app_user_id: 1059806, carnet: 178797, expected_id: 4299 },
  { action: 'enable', app_user_id: 1063519, carnet: 178833, expected_id: 4315 },
  { action: 'enable', app_user_id: 1063705, carnet: 179023, expected_id: 4363 },
  { action: 'enable', app_user_id: 1063888, carnet: 179208, expected_id: 4395 },
  { action: 'enable', app_user_id: 1064002, carnet: 179325, expected_id: 4420 },
  { action: 'enable', app_user_id: 1064012, carnet: 179336, expected_id: 4424 },
  { action: 'enable', app_user_id: 1064019, carnet: 179343, expected_id: 4425 },
  { action: 'enable', app_user_id: 1064187, carnet: 179425, expected_id: 9821 },
  { action: 'enable', app_user_id: 1069836, carnet: 179595, expected_id: 9691 },
  { action: 'enable', app_user_id: 1069885, carnet: 179650, expected_id: 9782 },
  { action: 'enable', app_user_id: 1069997, carnet: 179763, expected_id: 4502 },
  { action: 'enable', app_user_id: 1070065, carnet: 179834, expected_id: 4512 },
  { action: 'enable', app_user_id: 1070078, carnet: 179847, expected_id: 4518 },
  { action: 'enable', app_user_id: 1070129, carnet: 179905, expected_id: 4530 },
  { action: 'enable', app_user_id: 1070684, carnet: 179980, expected_id: 6316 },
  { action: 'enable', app_user_id: 1074704, carnet: 180043, expected_id: 4561 },
  { action: 'enable', app_user_id: 1074785, carnet: 180130, expected_id: 4585 },
  { action: 'enable', app_user_id: 1079746, carnet: 180659, expected_id: 4702 },
  { action: 'enable', app_user_id: 1079762, carnet: 180675, expected_id: 4697 },
  { action: 'enable', app_user_id: 1079766, carnet: 180679, expected_id: 4699 },
  { action: 'enable', app_user_id: 1088079, carnet: 181085, expected_id: 4780 },
  { action: 'enable', app_user_id: 1092375, carnet: 181198, expected_id: 9888 },
  { action: 'enable', app_user_id: 1092406, carnet: 181231, expected_id: 4825 },
  { action: 'enable', app_user_id: 1093465, carnet: 181561, expected_id: 9783 },
  { action: 'enable', app_user_id: 1102167, carnet: 181732, expected_id: 4992 },
  { action: 'enable', app_user_id: 1121874, carnet: 183336, expected_id: 6791 },
  { action: 'enable', app_user_id: 1122005, carnet: 183469, expected_id: 5517 },
  { action: 'enable', app_user_id: 1129308, carnet: 183653, expected_id: 9889 },
  { action: 'enable', app_user_id: 1138665, carnet: 184371, expected_id: 5822 },
  { action: 'disable', app_user_id: 1271833, carnet: 151775, expected_id: 3652 },
  { action: 'disable', app_user_id: 1271425, carnet: 170700, expected_id: 3139 },
  { action: 'disable', app_user_id: 1271315, carnet: 170718, expected_id: 3147 },
  { action: 'disable', app_user_id: 1271448, carnet: 170719, expected_id: 3148 },
  { action: 'disable', app_user_id: 1271569, carnet: 171281, expected_id: 3396 },
  { action: 'disable', app_user_id: 1271562, carnet: 171511, expected_id: 3398 },
  { action: 'disable', app_user_id: 1271491, carnet: 171639, expected_id: 3313 },
  { action: 'disable', app_user_id: 1271553, carnet: 171835, expected_id: 3393 },
  { action: 'disable', app_user_id: 1271657, carnet: 172220, expected_id: 3434 },
]

done_count = 0
skipped_count = 0
failed_count = 0

puts ['action','app_user_id','carnet','resolved_id','outcome','activity_id','created_at','detail'].join('@')

Database.with_connection do |connection|
  targets.each do |target|
    users = connection.fetch(:users, { external_id: target[:carnet] })

    if users.size != 1
      skipped_count += 1
      puts [target[:action], target[:app_user_id], target[:carnet], '', 'skipped', '', '', "resolved #{users.size} users"].join('@')
      next
    end

    resolved_id = users.first[:id]
    if resolved_id.to_s != target[:expected_id].to_s
      skipped_count += 1
      puts [target[:action], target[:app_user_id], target[:carnet], resolved_id, 'skipped', '', '', "id drift (expected #{target[:expected_id]})"].join('@')
      next
    end

    procedure = target[:action] == 'enable' ? 'enable_user' : 'disable_user'

    begin
      result = connection.execute_procedure(name: procedure, params: "@user_id=#{resolved_id}, @mode='DEBUG'")
      inserted = result.is_a?(Array) ? result.first : nil
      done_count += 1
      activity_id = inserted ? inserted[:id] : ''
      created_at = inserted ? inserted[:created_at] : ''
      puts [target[:action], target[:app_user_id], target[:carnet], resolved_id, 'done', activity_id, created_at, procedure].join('@')
    rescue => error
      failed_count += 1
      puts [target[:action], target[:app_user_id], target[:carnet], resolved_id, 'failed', '', '', error.message].join('@')
    end
  end
end

puts "SUMMARY@done=#{done_count}@skipped=#{skipped_count}@failed=#{failed_count}@total=#{targets.size}"
nil
