#!/bin/bash

bindings=""

# Vérifier si le fichier .env existe
if [[ ! -f .env ]]; then
  echo ""
  exit 0
fi

while IFS= read -r line || [ -n "$line" ]; do
  if [[ ! "$line" =~ ^# ]] && [[ -n "$line" ]]; then
    name=$(echo "$line" | cut -d '=' -f 1)
    value=$(echo "$line" | cut -d '=' -f 2-)
    value=$(echo $value | sed 's/^"\(.*\)"$/\1/')
    bindings+="--binding ${name}=${value} "
  fi
done < .env

bindings=$(echo $bindings | sed 's/[[:space:]]*$//')

echo $bindings