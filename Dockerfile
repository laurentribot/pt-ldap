FROM debian:9.7-slim as openldap

COPY proxy.apt /etc/apt/apt.conf.d/00proxy

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install libssl-dev openssl patch autoconf gcc libtool libsasl2-dev make libperl-dev groff-base -y
#RUN curl -s -o openldap-2.4.47.tgz ftp://ftp.openldap.org/pub/OpenLDAP/openldap-release/openldap-2.4.47.tgz && \
COPY openldap-2.4.47.tgz .
RUN tar xzf openldap-2.4.47.tgz
#    curl -s -o openldap-2.4.47-consolidated-1.patch http://www.linuxfromscratch.org/patches/blfs/svn/openldap-2.4.47-consolidated-1.patch
COPY openldap-2.4.47-consolidated-1.patch .
RUN cd openldap-2.4.47/ && \
    patch -Np1 -i ../openldap-2.4.47-consolidated-1.patch && \
    autoconf && \
    ./configure --prefix=/usr \
                --sysconfdir=/etc \
                --localstatedir=/var \
                --libexecdir=/usr/lib \
                --disable-static \
                --enable-debug \
                --with-tls=openssl \
                --with-cyrus-sasl \
                --enable-dynamic \
                --enable-crypt \
                --enable-spasswd \
                --enable-slapd \
                --enable-modules \
                --enable-rlookups \
                --enable-backends=mod \
                --disable-ndb \
                --disable-sql \
                --disable-shell \
                --disable-bdb \
                --disable-hdb \
                --enable-overlays=mod && \
    make depend && \
    make && \
    make install

RUN mkdir -p /opt/dist/etc/openldap /opt/dist/var/lib/openldap /opt/dist/var/run/openldap /opt/dist/usr/lib/openldap /opt/dist/usr/lib/x86_64-linux-gnu /opt/dist/usr/bin /opt/dist/usr/sbin && \
    cp -rp /etc/openldap /opt/dist/etc/ && \
    cp -rp /usr/lib/openldap /opt/dist/usr/lib/ && \
    cp -p /usr/lib/x86_64-linux-gnu/libltdl.so.7* /opt/dist/usr/lib/x86_64-linux-gnu/ && \
    cp -p /usr/bin/ldap* /opt/dist/usr/bin/ && \
    cp -p /usr/sbin/slap* /opt/dist/usr/sbin/ && \
    cp -p /usr/lib/liblber* /opt/dist/usr/lib/ && \
    cp -p /usr/lib/libldap* /opt/dist/usr/lib/ && \
    sed -e "s/\.la/.so/" -i /opt/dist/etc/openldap/slapd.*

RUN mkdir -p /opt/dist/usr/lib/x86_64-linux-gnu/pkgconfig /opt/dist/usr/lib/x86_64-linux-gnu/sasl2 && \
    cp -p /usr/lib/x86_64-linux-gnu/pkgconfig/libsasl2.pc /opt/dist/usr/lib/x86_64-linux-gnu/pkgconfig && \
    cp -rp /usr/lib/x86_64-linux-gnu/sasl2 /opt/dist/usr/lib/x86_64-linux-gnu && \
    cp -p /usr/lib/x86_64-linux-gnu/libsasl2* /opt/dist/usr/lib/

RUN mkdir -p /opt/dist/usr/lib/sasl2/ && \
    echo "mech_list: plain" > /opt/dist/usr/lib/sasl2/slapd.conf && \
    echo "pwcheck_method: saslauthd" >> /opt/dist/usr/lib/sasl2/slapd.conf && \
    echo "saslauthd_path: /var/run/saslauthd/mux" >> /opt/dist/usr/lib/sasl2/slapd.conf

RUN mkdir -p /opt/dist/etc/openldap/ssl && \
    openssl req -days 5000 -newkey rsa:4096 -keyout /opt/dist/etc/openldap/ssl/openldap.key -nodes -sha256 -x509 -out /opt/dist/etc/openldap/ssl/openldap.pem -batch && \
    chmod 400 /opt/dist/etc/openldap/ssl/openldap.key && \
    cat /opt/dist/etc/openldap/ssl/openldap.pem >> /opt/dist/etc/openldap/ssl/cacerts.pem


FROM debian:9.7-slim as sasl

COPY proxy.apt /etc/apt/apt.conf.d/00proxy

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install libssl-dev patch autoconf gcc libtool make libldap2-dev unzip groff groff-base -y

COPY cyrus-sasl-cyrus-sasl-2.1.27.zip .
RUN unzip cyrus-sasl-cyrus-sasl-2.1.27.zip
RUN cd cyrus-sasl-cyrus-sasl-2.1.27/ && \
    ./autogen.sh --with-ldap=/usr --with-openssl=/usr --prefix=/usr && \
    make && \
    make install || make install

RUN mkdir -p /opt/dist/usr/sbin /opt/dist/usr/lib/sasl2 /opt/dist/usr/lib/pkgconfig && \
    cp -p /usr/sbin/pluginviewer /opt/dist/usr/sbin && \
    cp -p /usr/sbin/saslauthd /opt/dist/usr/sbin && \
    cp -p /usr/sbin/testsaslauthd /opt/dist/usr/sbin && \
    cp -rp /usr/lib/pkgconfig /opt/dist/usr/lib && \
    cp -rp /usr/lib/sasl2 /opt/dist/usr/lib && \
    cp -p /usr/lib/libsasl2* /opt/dist/usr/lib/ && \
    mkdir -p /opt/dist/var/state/saslauthd


FROM golang:1.11 as wrapper

COPY pt-ldap.go .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o pt-ldap pt-ldap.go


FROM debian:9.7-slim
#FROM gcr.io/distroless/base:debug

COPY proxy.apt /etc/apt/apt.conf.d/00proxy

RUN apt-get update && apt-get install libssl1.1 -y

COPY --from=openldap /opt/dist/ /
COPY --from=sasl /opt/dist/ /
COPY --from=wrapper /go/pt-ldap /usr/sbin/pt-ldap

EXPOSE 389
EXPOSE 686

ENTRYPOINT ["/usr/sbin/pt-ldap"]
