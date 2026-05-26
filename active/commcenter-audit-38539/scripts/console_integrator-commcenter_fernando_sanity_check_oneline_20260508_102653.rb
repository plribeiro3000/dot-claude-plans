# Sanity check Fernando Da Costa Duschitz no integrator commcenter (oneline blocks)
# Stack: integrator-commcenter (production)
# Cada chamada Database.with_connection eh oneline pra evitar problema de paste em IRB

total_users = Database.with_connection { |adapter| adapter.count(:users) }
puts "=== SANITY 1: total de users na base normalizada -- count: #{total_users} ==="

sample_user = Database.with_connection { |adapter| adapter.first(:users) }
puts "=== SANITY 2: primeira row -- columns: #{sample_user.nil? ? 'NIL' : sample_user.keys.inspect} ==="
puts sample_user.inspect

samuel_results = Database.with_connection { |adapter| adapter.fetch(:users, Sequel.lit("LOWER(first_name) LIKE ?", '%samuel%')) }
puts "=== SANITY 3 controle samuel: hits=#{samuel_results.size} ==="
samuel_results.each { |row| puts "  id=#{row[:id]} first_name=#{row[:first_name].inspect} last_name=#{row[:last_name].inspect}" }

fernando_first = Database.with_connection { |adapter| adapter.fetch(:users, Sequel.lit("LOWER(first_name) LIKE ?", '%fernando%')) }
puts "=== Hits first_name LIKE fernando: #{fernando_first.size} ==="
fernando_first.each { |row| puts "  id=#{row[:id]} first_name=#{row[:first_name].inspect} last_name=#{row[:last_name].inspect} type=#{row[:type].inspect}" }

fernando_last = Database.with_connection { |adapter| adapter.fetch(:users, Sequel.lit("LOWER(last_name) LIKE ?", '%fernando%')) }
puts "=== Hits last_name LIKE fernando: #{fernando_last.size} ==="
fernando_last.each { |row| puts "  id=#{row[:id]} first_name=#{row[:first_name].inspect} last_name=#{row[:last_name].inspect} type=#{row[:type].inspect}" }

duschitz_first = Database.with_connection { |adapter| adapter.fetch(:users, Sequel.lit("LOWER(first_name) LIKE ?", '%duschitz%')) }
puts "=== Hits first_name LIKE duschitz: #{duschitz_first.size} ==="
duschitz_first.each { |row| puts "  id=#{row[:id]} first_name=#{row[:first_name].inspect} last_name=#{row[:last_name].inspect} type=#{row[:type].inspect}" }

duschitz_last = Database.with_connection { |adapter| adapter.fetch(:users, Sequel.lit("LOWER(last_name) LIKE ?", '%duschitz%')) }
puts "=== Hits last_name LIKE duschitz: #{duschitz_last.size} ==="
duschitz_last.each { |row| puts "  id=#{row[:id]} first_name=#{row[:first_name].inspect} last_name=#{row[:last_name].inspect} type=#{row[:type].inspect}" }
