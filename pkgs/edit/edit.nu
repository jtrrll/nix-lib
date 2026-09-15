#!/usr/bin/env nu

def main [
  --terminal,
  ...args: string
] {
  let editor = if $terminal {
    $env.EDITOR
  } else {
    $env.VISUAL
  }

  if ($editor | is-empty) {
    error make {
      msg: "Editor not set"
      help: "Set $EDITOR or $VISUAL in your environment"
    }
  }

  run-external $editor ...$args
}
