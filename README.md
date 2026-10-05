# bashutils
bash scripting utilities include file 

## use case

Whether in a new project or in an existing one, we assume you want to use a bash script, `helper.sh`, 
to provide bash functions that can be used both in ci-cd/devops pipelines/workflows and in our local systems.

This way we intend to shift away from chaotic one-off commands and functions and leverage reusable solutions and patterns across distinct projects.

### one-liner setup

download a helper script for a new project with:

```bash
curl -fsSL https://raw.githubusercontent.com/tgedr/bashutils/main/bashutils-template.sh -o ./helper.sh && chmod +x ./helper.sh
```

if eventually you experience issues with the corporation proxy, you still have 2 options:

- try the api:

```bash
curl -fsSL "https://api.github.com/repos/tgedr/bashutils/contents/bashutils-template.sh" \
  | python3 -c "import sys,json,base64; print(base64.b64decode(json.load(sys.stdin)['content']).decode())" \
    > ./helper.sh && chmod +x ./helper.sh
```

- try using the `gh` cli:

```bash
gh api repos/tgedr/bashutils/contents/bashutils-template.sh \
  --jq '.content' | base64 -d > ./helper.sh && chmod +x ./helper.sh
```

the downloaded file is a regular bash script that you can rename and customize for your project.

### `helper.sh` usage

- when invoked, `helper.sh`, if non-existent it creates the files `.variables` (should be version-managed), `.local_variables` and `.secrets` (these latest 2 are for personal development purposes and should NOT be version-managed) next to the script
- you should at first download `bashutils`: `./helper.sh update_bashutils`
- it provides a set of logging functions
- `bashutils` functions are included in `helper.sh`:
  ```
  export INCLUDE_FILE=${INCLUDE_FILE:-"bashutils"}
  ...
  # ---------- include bashutils ----------
  BASHUTILS_AUTO_UPDATE="${BASHUTILS_AUTO_UPDATE:-0}"
  update_bashutils
  . "$this_folder/$INCLUDE_FILE"
  ```
- we can automate the bashutils update by adding to `.local_variables`:
  ```
  export BASHUTILS_AUTO_UPDATE=1
  ```

- you can now reuse `bashutils` functions by referencing functions in your own `helper.sh`:
  ```bash
  case "$1" in
    update_bashutils)
      BASHUTILS_AUTO_UPDATE=1 update_bashutils "$2"
      ;;
    reqs)
      reqs
      ;;
    verify_env)
      verify_env
      ;;
    collect_dot_git)
      collect_dot_git "$2"
      ;;
    databricks_bundle_deploy)
      databricks_bundle_deploy "$2" "$3"
      ;;
    databricks_bundle_destroy)
      databricks_bundle_destroy "$2" "$3"
      ;;
    *)
      usage
      ;;
  esac
  ```
- you can also add your own functions directly to the `.helper.sh` script
- you are encouraged to submit PR's to contribute with new functionality to `bashutils`

## contributing

- requirements:
  - bash
  - sha256sum
  - python 3
- treat `sections/` as the source of truth for `bashutils`
- after updating `sections/`, regenerate `bashutils` with:

  ```bash
  ./helper.sh build
  ```
- have a look into the CI workflow in `.github/workflows/ci.yml`

- push the changes in `sections/*` source files in a PR

## tests

this repository uses [bats-core](https://github.com/bats-core/bats-core) for tests:

```bash
./helper.sh test
```
