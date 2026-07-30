#!/bin/bash
# Reproducer: heredoc inside $( ) with multiple occurrences in the same script.
# Shape A: two independent command substitutions, each with its own heredoc,
# executed back to back (the shape most likely to appear in a hook script that
# builds two separate JSON strings for additionalContext, one per branch).

first=$(cat <<'EOF'
{"line1": "alpha"}
EOF
)

second=$(cat <<'EOF'
{"line2": "beta"}
EOF
)

echo "A_FIRST=[$first]"
echo "A_SECOND=[$second]"

# Shape B: two heredocs sequentially INSIDE the same single $( ... ) group.
combined=$(
  cat <<'ONE'
part-one
ONE
  cat <<'TWO'
part-two
TWO
)

echo "B_COMBINED=[$combined]"

# Shape C: heredoc inside $( ) used as an argument to a function, called twice.
build_message() {
  cat <<EOF
label=$1
EOF
}

first_call=$(build_message "x")
second_call=$(build_message "y")

echo "C_FIRST=[$first_call]"
echo "C_SECOND=[$second_call]"
