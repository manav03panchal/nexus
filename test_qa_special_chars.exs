# QA: Test special characters and command injection attempts
host :decaflab, "decafcoffee@100.112.64.66"

task :test_special_chars, on: :decaflab do
  # Test with spaces in filename
  file "/tmp/file with spaces.txt",
    state: :present,
    content: "test content"

  command "cat '/tmp/file with spaces.txt'"

  # Cleanup
  file "/tmp/file with spaces.txt", state: :absent

  # Test with quotes in content
  file "/tmp/quotes_test.txt",
    state: :present,
    content: "He said \"hello\" and 'goodbye'"

  command "cat /tmp/quotes_test.txt"
  file "/tmp/quotes_test.txt", state: :absent

  # Test with backticks (potential command injection)
  file "/tmp/backtick_test.txt",
    state: :present,
    content: "This has `backticks` in it"

  command "cat /tmp/backtick_test.txt"
  file "/tmp/backtick_test.txt", state: :absent

  # Test with dollar signs (variable expansion)
  file "/tmp/dollar_test.txt",
    state: :present,
    content: "Price is $100 and $HOME should not expand"

  command "cat /tmp/dollar_test.txt"
  file "/tmp/dollar_test.txt", state: :absent
end
