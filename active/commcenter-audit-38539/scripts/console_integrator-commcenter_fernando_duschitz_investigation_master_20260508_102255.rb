# Investigacao Fernando Da Costa Duschitz no integrator commcenter (MASTER)
# Stack: integrator-commcenter (production)
# Schema fsk_users: id, first_name, last_name, email, unique_register_id, register_type, type, parent_id, subsidiary_id, anonymized, created_at, updated_at
# CONCAT(first_name, ' ', last_name) usado pra cobrir variacoes de onde o cliente coloca "Da Costa" / "Duschitz"

primary_results = Database.with_connection do |adapter|
  adapter.fetch(:users, Sequel.lit("LOWER(CONCAT(first_name, ' ', last_name)) LIKE ?", '%fernando%duschitz%'))
end

puts "=== fsk_users com CONCAT(first_name, ' ', last_name) LIKE %fernando%duschitz% ==="
puts "hits: #{primary_results.size}"
primary_results.each_with_index do |row, index|
  puts "--- row #{index + 1} ---"
  row.each { |key, value| puts "  #{key}: #{value.inspect}" }
end
puts ''

fallback_results = Database.with_connection do |adapter|
  adapter.fetch(
    :users,
    Sequel.lit(
      "LOWER(CONCAT(first_name, ' ', last_name)) LIKE ? AND (LOWER(CONCAT(first_name, ' ', last_name)) LIKE ? OR LOWER(CONCAT(first_name, ' ', last_name)) LIKE ?)",
      '%fernando%',
      '%costa%',
      '%duschitz%'
    )
  )
end

puts "=== fallback fsk_users com fernando + (costa OR duschitz) ==="
puts "hits: #{fallback_results.size}"
fallback_results.each_with_index do |row, index|
  puts "--- row #{index + 1} ---"
  row.each { |key, value| puts "  #{key}: #{value.inspect}" }
end
puts ''

candidates = (primary_results + fallback_results).uniq { |row| row[:id] }

if candidates.empty?
  puts '=== Nao foi encontrado nenhum Fernando Da Costa Duschitz na base normalizada. ==='
else
  puts "=== Para cada candidato, busca o Resource User no Mongo ==="
  candidates.each_with_index do |row, index|
    external_id_str = row[:id].to_s
    full_name = "#{row[:first_name]} #{row[:last_name]}"
    puts "--- candidato #{index + 1}: name=#{full_name.inspect} id=#{external_id_str} ---"

    resource = User.where(external_id: external_id_str).first

    if resource.nil?
      puts '  Nenhum Resource User encontrado no Mongo (nunca foi tentada integracao)'
      next
    end

    puts "  Resource encontrado:"
    puts "    integration_status: #{resource.integration_status}"
    puts "    model_version: #{resource.model_version}"
    puts "    imports.size: #{resource.imports.size}"
    puts "    created_at: #{resource.created_at}"
    puts "    updated_at: #{resource.updated_at}"

    resource.imports.each_with_index do |import, import_index|
      puts "  --- Import #{import_index + 1} ---"
      puts "    job_id: #{import.job_id}"
      puts "    data: #{import.data.inspect}"
      puts "    requests.size: #{import.requests.size}"

      import.requests.each_with_index do |request, request_index|
        puts "    --- Request #{request_index + 1} ---"
        puts "      http_method: #{request.http_method}"
        puts "      url: #{request.url}"
        puts "      timestamp: #{request.timestamp}"
        puts "      body: #{request.body.to_s[0..500]}"

        if request.response.present?
          response_body_text = request.response.body.is_a?(String) ? request.response.body : request.response.body.inspect
          puts "      response.status: #{request.response.status}"
          puts "      response.body: #{response_body_text[0..1000]}"
        else
          puts '      response: NIL'
        end
      end
    end
  end
end
