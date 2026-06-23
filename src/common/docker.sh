# ============================================
# Docker image acquisition (Docker Hub rate-limit / RU-block resilient)
# ============================================
# Mirrors tried (in order) when a direct Docker Hub pull fails:
#   - mirror.gcr.io        Google's pull-through cache of Docker Hub library
#                          images. Trusted, RU-reachable, and pulls do NOT count
#                          against Docker Hub rate limits. Tried first.
#   - the rest             RU-reachable community mirrors, last resort only
#                          (logged when used — they could substitute images).
# Each mirror image is re-tagged to the bare reference (nginx:TAG)
# so the unchanged docker-compose `image:` and `docker run ... validate` reuse
# the local image with no further registry I/O.
DOCKER_HUB_MIRRORS=("mirror.gcr.io" "dockerhub.timeweb.cloud" "huecker.io" "cr.yandex/mirror")

# ensure_image <bare-ref> [force_pull]   e.g. nginx:1.29.3-alpine
# Guarantees the bare ref exists locally. Returns 0 on success, 1 if the image
# cannot be obtained from Docker Hub or any mirror.
ensure_image() {
    local ref="$1"
    local force_pull="${2:-false}"
    local repo="${ref%%:*}"
    local tag="${ref##*:}"

    # 0) Already present locally (and not forcing a pull) — nothing to do.
    if [ "$force_pull" != "true" ] && docker image inspect "$ref" >/dev/null 2>&1; then
        return 0
    fi

    log_info "Fetching Docker image: $ref"

    # 1) Direct pull — Docker Hub, or via `docker login` creds / daemon.json mirror.
    local out
    if out=$(docker pull "$ref" 2>&1); then
        return 0
    fi

    # Only fall back to mirrors for registry/rate-limit/network problems.
    if echo "$out" | grep -qiE 'pull rate limit|unauthenticated pull|toomanyrequests|error from registry|manifest unknown|manifest for .* not found|not found: manifest|no such host|connection refused|i/o timeout|timeout exceeded|tls handshake|denied|forbidden'; then
        log_warning "Direct pull of $ref failed (Docker Hub rate limit or block). Trying mirrors..."
    else
        log_error "docker pull failed for $ref:"
        echo "$out" | tail -3
        return 1
    fi

    # 2) Mirror fallback: pull via explicit registry path, then retag to bare ref.
    local mirror src
    for mirror in "${DOCKER_HUB_MIRRORS[@]}"; do
        if [ "$mirror" = "cr.yandex/mirror" ]; then
            src="$mirror/$repo:$tag"          # Yandex: no /library segment
        else
            src="$mirror/library/$repo:$tag"
        fi
        if docker pull "$src" >/dev/null 2>&1; then
            if docker tag "$src" "$ref" >/dev/null 2>&1; then
                docker rmi "$src" >/dev/null 2>&1 || true
                if [ "$mirror" = "mirror.gcr.io" ]; then
                    log_success "Image obtained via $mirror (Google cache): $ref"
                else
                    log_warning "Image obtained via fallback mirror '$mirror': $ref"
                fi
                return 0
            fi
        fi
    done

    log_error "Could not obtain image $ref from Docker Hub or any mirror."
    echo -e "${GRAY}   Options:${NC}"
    echo -e "${GRAY}     • docker login                                  # raises the pull limit${NC}"
    echo -e "${GRAY}     • add a registry mirror to /etc/docker/daemon.json, then: systemctl restart docker${NC}"
    echo -e "${GRAY}     • retry later (Docker Hub anonymous limit resets in ~6h)${NC}"
    return 1
}

# Ensure the image for the currently selected web server is present locally.
ensure_runtime_image() {
    local force_pull="${1:-false}"
    ensure_image "nginx:${NGINX_VERSION}" "$force_pull"
}
