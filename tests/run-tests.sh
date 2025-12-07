#!/bin/bash
# Test Suite

echo "Running Mesh Network Tests..."
echo

# ShellCheck
echo "1. Running shellcheck..."
find ../scripts ../tools -name "*.sh" -exec shellcheck {} \; && echo "✓ Shellcheck passed" || echo "✗ Shellcheck failed"

echo
echo "2. Checking file structure..."
[ -f ../install.sh ] && echo "✓ install.sh exists" || echo "✗ install.sh missing"
[ -f ../README.md ] && echo "✓ README.md exists" || echo "✗ README.md missing"

echo
echo "✓ Tests completed!"
