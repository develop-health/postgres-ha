ARG PG_VERSION=14.4
ARG VERSION=custom

FROM golang:1.16 as flyutil
ARG VERSION

WORKDIR /go/src/github.com/fly-examples/postgres-ha
COPY . .

RUN CGO_ENABLED=0 GOOS=linux go build -v -o /fly/bin/flyadmin ./cmd/flyadmin
RUN CGO_ENABLED=0 GOOS=linux go build -v -o /fly/bin/start ./cmd/start

RUN CGO_ENABLED=0 GOOS=linux go build -v -o /fly/bin/pg-restart ./.flyctl/cmd/pg-restart
RUN CGO_ENABLED=0 GOOS=linux go build -v -o /fly/bin/pg-role ./.flyctl/cmd/pg-role
RUN CGO_ENABLED=0 GOOS=linux go build -v -o /fly/bin/pg-failover ./.flyctl/cmd/pg-failover
RUN CGO_ENABLED=0 GOOS=linux go build -v -o /fly/bin/stolonctl-run ./.flyctl/cmd/stolonctl-run
RUN CGO_ENABLED=0 GOOS=linux go build -v -o /fly/bin/pg-settings ./.flyctl/cmd/pg-settings

COPY ./bin/* /fly/bin/

FROM flyio/stolon:2e719de as stolon

FROM wrouesnel/postgres_exporter:latest AS postgres_exporter

FROM supabase/postgres
ARG VERSION 
ARG POSTGIS_MAJOR=3
ARG WALG_VERSION=2.0.0

LABEL fly.app_role=postgres_cluster
LABEL fly.version=${VERSION}
LABEL fly.pg-version=${PG_VERSION}

RUN apt-get update && apt-get install --no-install-recommends -y \
    ca-certificates curl bash dnsutils vim-tiny procps jq haproxy \
    postgresql-$PG_MAJOR-postgis-$POSTGIS_MAJOR \
    postgresql-$PG_MAJOR-postgis-$POSTGIS_MAJOR-scripts \    
    && apt autoremove -y \
    && echo 'Installing wal-g' \
    && curl -L https://github.com/wal-g/wal-g/releases/download/v${WALG_VERSION}/wal-g-pg-ubuntu-18.04-amd64 > /usr/local/bin/wal-g \
    && chmod +x /usr/local/bin/wal-g

COPY --from=stolon /go/src/app/bin/* /usr/local/bin/
COPY --from=postgres_exporter /postgres_exporter /usr/local/bin/

ADD /scripts/* /fly/
ADD /config/* /fly/
RUN useradd -ms /bin/bash stolon
RUN mkdir -p /run/haproxy/
COPY --from=flyutil /fly/bin/* /usr/local/bin/

ADD /init/* /docker-entrypoint-initdb.d/

EXPOSE 5432

CMD ["start"]
