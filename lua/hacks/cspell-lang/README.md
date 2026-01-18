# CSpell Multiple Language Support

This hack allows user to install and enable another language in cspell
with just a single command.

## Usage
```vim
:CSpellLangInstall pl
```

## What it does?

This command looks for place where cspell package is installed and then
it installs a package for a specific language. It also enables this language in `cspell.json`

## Languages

Due to inconsistent languages naming scheme currently each language needs to be enabled in code. \
New languages can be easily added. \
Language list: https://github.com/streetsidesoftware/cspell-dicts/tree/main/dictionaries

```lua
local lang_types = {
  pl = "dict-pl_pl",
  nl = "dict-nl-nl",
  hr = "dict-hr-hr",
  it = "dict-it-it",
}
```

## TODO
Currently it it hardcoded to work only with `cspell.json` inside nvim config dir. 
Add config to change that.

