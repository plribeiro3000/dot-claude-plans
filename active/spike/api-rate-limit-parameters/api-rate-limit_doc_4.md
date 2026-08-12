# Auxiliary source 4 — Rack::Attack and fail2ban ban durations (verbatim excerpts)

Fetched 2026-08-11. Each entry records the URL and the literal strings confirmed present on the page.

---

## Rack::Attack README

URL: https://raw.githubusercontent.com/rack/rack-attack/main/README.md

Throttle examples (counting period, no ban duration):

```ruby
Rack::Attack.throttle("requests by ip", limit: 5, period: 2) do |request|
  request.ip
end
```

```ruby
Rack::Attack.throttle('limit logins per email', limit: 6, period: 60) do |req|
  if req.path == '/login' && req.post?
    req.params['email'].to_s.downcase.gsub(/\s+/, "")
  end
end
```

```ruby
limit_proc = proc { |req| req.env["REMOTE_USER"] == "admin" ? 100 : 1 }
period_proc = proc { |req| req.env["REMOTE_USER"] == "admin" ? 1 : 60 }

Rack::Attack.throttle('request per ip', limit: limit_proc, period: period_proc) do |request|
  request.ip
end
```

Fail2Ban example — carries an explicit ban duration:

```ruby
Rack::Attack.blocklist('fail2ban pentesters') do |req|
  Rack::Attack::Fail2Ban.filter("pentesters-#{req.ip}", maxretry: 3, findtime: 10.minutes, bantime: 5.minutes) do
    CGI.unescape(req.query_string) =~ %r{/etc/passwd} ||
    req.path.include?('/etc/passwd') ||
    req.path.include?('wp-admin') ||
    req.path.include?('wp-login')
  end
end
```

Allow2Ban example — carries an explicit ban duration:

```ruby
Rack::Attack.blocklist('allow2ban login scrapers') do |req|
  Rack::Attack::Allow2Ban.filter(req.ip, maxretry: 20, findtime: 1.minute, bantime: 1.hour) do
    req.path == '/login' and req.post?
  end
end
```

---

## fail2ban shipped defaults

URL: https://raw.githubusercontent.com/fail2ban/fail2ban/master/config/jail.conf

```
# "bantime" is the amount of time that a host is banned, integer in seconds or
# time abbreviation format (m - minutes, h - hours, d - days, w - weeks, mo - months, y - years).
# This is to consider as an initial time if bantime.increment gets enabled.
bantime  = 10m

# A host is banned if it has generated "maxretry" during the last "findtime"
# seconds.
findtime  = 10m

# "maxretry" is the number of failures before a host get banned.
maxretry = 5
```
