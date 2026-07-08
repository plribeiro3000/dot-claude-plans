# ---------------------------------------------------------------------------
# APP MUTATION - Atento MX orphan bajas disabled directly in the app
# Paste into: bin/ecs run atento-001   (Rails console)
# These 162 are active in the app but absent from the normalized base, so the
# integrator cannot reach them; they are disabled here with disabler nil (the
# same convention as the automated/integrator disables). ApplicationRecord#disable
# guards against already-disabled (returns false, no raise). Continue-on-error.
# Output @-separated for Excel.
# ---------------------------------------------------------------------------
company = Company.find(1318)

user_ids = [
  1025914, 993919, 1025419, 1037901, 1026008, 1121779, 1037957, 998390, 1129129, 991417, 996932, 1038187,
  1115748, 1038209, 1038210, 1069760, 1038292, 996597, 1063446, 996945, 1074659, 1248452, 991390, 1038511,
  1138596, 1026642, 1038563, 1027912, 1038697, 1038702, 993805, 995649, 1038768, 996230, 996231, 1007225,
  996243, 1038959, 1039044, 996561, 1022386, 993928, 1069793, 991209, 994805, 994143, 1039327, 991797,
  1063484, 996151, 1039522, 990860, 994304, 1026128, 993930, 1025743, 1023023, 1129148, 1039720, 1022227,
  991952, 1022193, 1002952, 1035299, 1039894, 1023513, 1040097, 1040126, 1040234, 1040390, 1059240, 1059249,
  1059423, 1059514, 1059717, 1063881, 1064184, 1064278, 1070106, 1070675, 1079542, 1088039, 1092340, 1092449,
  1092454, 1092458, 1093490, 1102256, 1102385, 1109421, 1109518, 1112066, 1115819, 1115889, 1115892, 1116081,
  1117584, 1117608, 1121947, 1121982, 1122002, 1129187, 1129194, 1129316, 1132572, 1132591, 1132681, 1138411,
  1138419, 1138444, 1138655, 1138687, 1138745, 1144279, 1144328, 1144448, 1144459, 1144464, 1248478, 1248491,
  1248556, 1253703, 1253726, 1253746, 1253749, 1253777, 1253816, 1253818, 1253829, 1253879, 1253886, 1253887,
  1260532, 1260563, 1260614, 1260623, 1260631, 1260646, 1260665, 1260683, 1260711, 1260728, 1260737, 1260746,
  1260777, 1260778, 1260782, 1260801, 1260807, 1260811, 1266676, 1266678, 1266729, 1266743, 1266765, 1266768,
  1266770, 1266777, 1266838, 1266855, 1266863, 1266939,
]

done_count = 0
skipped_count = 0
failed_count = 0

puts ['app_user_id','outcome','disabled_at','detail'].join('@')

user_ids.each do |user_id|
  user = company.users.find_by(id: user_id)

  if user.nil?
    skipped_count += 1
    puts [user_id, 'skipped', '', 'not_found'].join('@')
    next
  end

  if user.disabled?
    skipped_count += 1
    puts [user_id, 'skipped', user.disabled_at, 'already_inactive'].join('@')
    next
  end

  begin
    if user.disable(by: nil)
      done_count += 1
      puts [user_id, 'done', user.disabled_at, ''].join('@')
    else
      failed_count += 1
      puts [user_id, 'failed', '', user.errors.full_messages.join('; ')].join('@')
    end
  rescue => error
    failed_count += 1
    puts [user_id, 'failed', '', error.message].join('@')
  end
end

puts "SUMMARY@done=#{done_count}@skipped=#{skipped_count}@failed=#{failed_count}@total=#{user_ids.size}"
nil
