# Dentaku 3.5.7 — consolidated source excerpts consulted for this spike
#
# Gem location on this machine (app's gemset):
#   /Users/plribeiro3000/.rvm/gems/ruby-4.0.6@four_shark/gems/dentaku-3.5.7
#
# This file is a reference copy assembled from several gem source files, kept together
# because the spike's central claim (an unknown variable key parses cleanly and fails
# only at evaluation) depends on reading all of them in sequence. Each section names its
# real source file and line numbers as they exist in the installed gem.

# ---------------------------------------------------------------------------
# lib/dentaku.rb:16-18 — the bang entry point Rule#calculate! goes through
# ---------------------------------------------------------------------------
#   def self.evaluate!(expression, data = {}, &block)
#     calculator.value.evaluate!(expression, data, &block)
#   end

# ---------------------------------------------------------------------------
# lib/dentaku/calculator.rb:67-82 — Calculator#evaluate!
# This is where parsing and binding-checking are TWO SEPARATE STEPS.
# ---------------------------------------------------------------------------
#   def evaluate!(expression, data = {}, &block)
#     context = evaluation_context(data, :strict)
#     return evaluate_array!(expression, context, &block) if expression.is_a? Array
#
#     store(context) do
#       node = ast(expression)                       # <- tokenize + parse (grammar only)
#       unbound = node.dependencies(memory)           # <- binding check, SEPARATE step
#
#       unless unbound.empty?
#         raise UnboundVariableError.new(unbound),
#               "no value provided for variables: #{unbound.uniq.join(', ')}"
#       end
#
#       node.value(memory)
#     end
#   end

# ---------------------------------------------------------------------------
# lib/dentaku/calculator.rb:109-126 — Calculator#ast
# Confirms `ast(expression)` only tokenizes and parses; it never touches the
# data/options hash. Binding is not part of this call.
# ---------------------------------------------------------------------------
#   def ast(expression)
#     return expression if expression.is_a?(AST::Node)
#     return expression.map { |e| ast(e) } if expression.is_a? Array
#
#     @ast_cache.fetch(expression) {
#       options = {
#         aliases: aliases,
#         case_sensitive: case_sensitive,
#         function_registry: @function_registry,
#         raw_date_literals: raw_date_literals
#       }
#
#       tokens = tokenizer.tokenize(expression, options)
#       Parser.new(tokens, options).parse.tap do |node|
#         @ast_cache[expression] = node if cache_ast?
#       end
#     }
#   end

# ---------------------------------------------------------------------------
# lib/dentaku/parser.rb:118-142 — Parser#process_token
# The line that proves an identifier is NEVER checked against a binding at
# parse time — it is simply wrapped into an AST::Identifier node and pushed.
# Contrast with the :function branch (handle_function), which DOES raise a
# ParseError (:undefined_function) at parse time when the function name is
# not registered — this is the one case where an unknown NAME is caught
# during parsing rather than during evaluation.
# ---------------------------------------------------------------------------
#   def process_token(token, lookahead, index)
#     case token.category
#     when :datetime      then output << AST::DateTime.new(token)
#     when :numeric       then output << AST::Numeric.new(token)
#     when :logical       then output << AST::Logical.new(token)
#     when :string        then output << AST::String.new(token)
#     when :identifier    then output << AST::Identifier.new(token, case_sensitive: case_sensitive)
#     when :operator, :comparator, :combinator
#       handle_operator(token, lookahead)
#     when :null
#       output << AST::Nil.new
#     when :function
#       handle_function(token)
#     ...
#     end
#   end
#
#   def handle_function(token)
#     func = function(token)
#     fail! :undefined_function, function_name: token.value if func.nil?
#     arities.push 0
#     operations.push func
#   end

# ---------------------------------------------------------------------------
# lib/dentaku/ast/identifier.rb — the whole class
# `dependencies` is what Calculator#evaluate! calls on the AST root; for an
# Identifier node, it returns `[identifier]` (itself) when the identifier is
# NOT a key in the evaluation context/memory. This is the sole place an
# "unbound variable" is detected — it happens after the AST already exists.
# ---------------------------------------------------------------------------
#   class Identifier < Node
#     include StringCasing
#     attr_reader :identifier, :case_sensitive
#
#     def initialize(token, options = {})
#       @case_sensitive = options.fetch(:case_sensitive, false)
#       @identifier = standardize_case(token.value)
#     end
#
#     def value(context = {})
#       v = context.fetch(identifier) do
#         raise UnboundVariableError.new([identifier]),
#               "no value provided for variables: #{identifier}"
#       end
#       ...
#     end
#
#     def dependencies(context = {})
#       context.key?(identifier) ? dependencies_of(context[identifier], context) : [identifier]
#     end
#     ...
#   end

# ---------------------------------------------------------------------------
# lib/dentaku/exceptions.rb:1-12 — UnboundVariableError IS a Dentaku::Error
# Rule::PARSE_EXCEPTIONS lists Dentaku::Error first (app/models/rule.rb:10),
# so UnboundVariableError is caught by the same rescue as a syntax error.
# ---------------------------------------------------------------------------
#   class Error < StandardError
#     attr_accessor :recipient_variable
#   end
#
#   class UnboundVariableError < Error
#     attr_reader :unbound_variables
#
#     def initialize(unbound_variables)
#       @unbound_variables = unbound_variables
#     end
#   end

# ---------------------------------------------------------------------------
# lib/dentaku/token_scanner.rb:32-57 and :173-189 — scanner registration order
# and the :function vs :identifier regexes.
#
# `available_scanners` registers :function BEFORE :identifier, and the
# function regex `\w+!?\s*\(` matches "word characters immediately followed
# by an opening paren". Consequence: `sum(x)` tokenizes its `sum` as a
# :function token, never as an :identifier token — so a formula calling a
# function never produces an :identifier token for the function's name.
# This is why Formula#referenced_identifiers (which filters on
# `token.is?(:identifier)`) never picks up function names by construction,
# with no extra filtering logic needed in the app.
# ---------------------------------------------------------------------------
#   def self.available_scanners
#     [
#       :null, :whitespace, :datetime, :numeric, :hexadecimal,
#       :double_quoted_string, :single_quoted_string, :negate, :combinator,
#       :operator, :grouping, :array, :access, :case_statement, :comparator,
#       :boolean, :function, :identifier, :quoted_identifier
#     ]
#   end
#
#   def self.function
#     new(:function, '\w+!?\s*\(', lambda do |raw|
#       function_name = raw.gsub('(', '')
#       [
#         Token.new(:function, function_name.strip.downcase.to_sym, function_name),
#         Token.new(:grouping, :open, '(')
#       ]
#     end)
#   end
#
#   def self.identifier
#     new(:identifier, '[[[:word:]]\.]+\b', lambda { |raw| standardize_case(raw.strip) })
#   end
#
#   def self.quoted_identifier
#     new(:identifier, '`[^`]*`', lambda { |raw| raw.gsub(/^`|`$/, '') })
#   end
#
#   def self.boolean
#     new(:logical, '(true|false)\b', lambda { |raw| raw.strip.downcase == 'true' })
#   end
#
#   def self.case_statement
#     names = { open: 'case', close: 'end', then: 'then', when: 'when', else: 'else' }.invert
#     new(:case, '(case|end|then|when|else)\b', lambda { |raw| names[raw.downcase] })
#   end

# ---------------------------------------------------------------------------
# lib/dentaku/tokenizer.rb:66-68 — comment stripping happens before scanning,
# uniformly for every caller of Tokenizer#tokenize (both Calculator#ast and
# Formula#referenced_identifiers use the same Tokenizer class).
# ---------------------------------------------------------------------------
#   def strip_comments(input)
#     input.gsub(/\/\*[^*]*\*+(?:[^*\/][^*]*\*+)*\//, '')
#   end
