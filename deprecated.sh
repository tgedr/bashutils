############################
#   name: create_from_template_and_envvars
#   purpose: renders a template file by substituting named environment variables using sed, writing the result to a destination file
#   parameters: $1 (template file path), $2 (destination file path), $3+ (names of environment variables to substitute)
#   returns: 0 on success, 1 if fewer than 3 arguments are provided or sed fails
############################
create_from_template_and_envvars() {
  info "[create_from_template_and_envvars] ...( $@ )"
  local usage_msg=$'create_from_template_and_envvars: creates a file from a template substituting env vars:\nusage:\n    create_from_template_and_envvars TEMPLATE DESTINATION [ENVVARS...]'

  if [ -z "$3" ] ; then echo "$usage_msg" && return 1; fi

  local template="$1"
  local destination="$2"
  local vars="${@:3}"

  local expression=""
  for var in $vars
  do
    eval val=\${"$var"}
    #echo "$var: $val"
    expression="${expression}s/${var}/${val}/g;"
  done

  #echo "expression: $expression"
  sed "${expression}" "$template" > "$destination"
  if [ ! "$?" -eq "0" ]; then err "[create_from_template_and_envvars] sed command was not successful" && return 1; fi
  info "[create_from_template_and_envvars] ...done."
}

