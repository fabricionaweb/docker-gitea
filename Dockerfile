# syntax=docker/dockerfile:1-labs
FROM public.ecr.aws/docker/library/alpine:3.19 AS base
ENV TZ=UTC
WORKDIR /src

# source stage =================================================================
FROM base AS source

# get and extract source from git
ARG BRANCH
ARG VERSION
ADD https://github.com/go-gitea/gitea.git#${BRANCH:-v$VERSION} ./

# frontend stage ===============================================================
FROM base AS build-frontend

# build dependencies
RUN apk add --no-cache nodejs npm

# node_modules
COPY --from=source /src/package*.json ./
RUN npm ci --fund=false --audit=false

# frontend source and build
COPY --from=source /src/webpack.config.js ./
COPY --from=source /src/assets ./assets
COPY --from=source /src/public ./public
COPY --from=source /src/web_src ./web_src
ENV ENABLE_SOURCEMAP=false
RUN npx webpack

# build stage ==================================================================
FROM base AS build-backend

# dependencies
RUN apk add --no-cache build-base git && \
    apk add --no-cache go --repository=http://dl-cdn.alpinelinux.org/alpine/edge/community

# build dependencies
COPY --from=source /src/go.mod /src/go.sum ./
RUN go mod download

# build app
COPY --from=source /src ./
COPY --from=build-frontend /src/public ./public
# required for go-sqlite3
ENV CGO_ENABLED=1 CGO_CFLAGS="-D_LARGEFILE64_SOURCE"
ENV TAGS="bindata sqlite sqlite_unlock_notify"
ARG VERSION
RUN mkdir /build && \
    go generate -tags "$TAGS" ./... && \
    go build -tags "$TAGS" -trimpath -ldflags "-s -w \
        -X main.Version=v$VERSION -X \"main.Tags=$TAGS\"" \
        -o /build/

# runtime stage ================================================================
FROM base

ENV S6_VERBOSITY=0 S6_BEHAVIOUR_IF_STAGE2_FAILS=2 PUID=65534 PGID=65534
ENV GITEA_WORK_DIR=/config HOME=/config
WORKDIR /config
VOLUME /config
EXPOSE 2222 3000

# copy files
COPY --from=build-backend /build/gitea /app/
COPY ./rootfs/. /

# runtime dependencies
RUN apk add --no-cache gnupg openssh-server tzdata s6-overlay curl git

# run using s6-overlay
ENTRYPOINT ["/entrypoint.sh"]
