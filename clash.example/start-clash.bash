#!/usr/bin/env bash
# To start clash as a container, you should configure `config.yaml` for clash first

# https://github.com/Dreamacro/clash
# https://dreamacro.github.io/clash/
# https://hub.docker.com/u/dreamacro
# https://github.com/Dreamacro/clash/blob/master/Dockerfile

# https://hub.docker.com/r/dreamacro/clash/tags
declare -rg clash_image='dreamacro/clash:v1.18.0'

# https://dreamacro.github.io/clash/configuration/configuration-reference.html
declare -rg clash_config_path="$(dirname "$0")/config.yaml"
[[ -r "$clash_config_path" ]] || {
    echo "Clash config file '$clash_config_path' not exists!"
    exit 1
}

# https://dreamacro.github.io/clash/zh_CN/configuration/inbound.html
declare -rg clash_mixed_port="$(grep -oP '^mixed-port: *\K\d+.*' config.yaml)" || {
    echo "'mixed-port' not found in '$clash_config_path'"
    exit 1
}

# https://docs.docker.com/network/#published-ports
declare -rg clash_mixed_port_publish_ip='127.0.0.1'

docker run \
  --name "$(basename "$clash_image"|cut -d: -f1)" \
  --detach \
  --restart always \
  --env TZ='Asia/Shanghai' \
  --volume "$clash_config_path:/root/.config/clash/config.yaml:ro" \
  --publish "$clash_mixed_port_publish_ip:$clash_mixed_port:$clash_mixed_port" \
  "$clash_image"