require "kernel_exec"

# Several arguments run the program directly, without splitting or expanding them
exec("printf", "%s|", "one two", "$HOME", "*")
