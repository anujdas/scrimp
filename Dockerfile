FROM litaio/ruby

MAINTAINER appkr <juwonkim@me.com>

ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update &&\
    apt-get install --no-install-recommends -y git thrift-compiler &&\
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN cd /opt &&\
    git clone https://github.com/appkr/scrimp.git&&\
    cd scrimp &&\
    gem build scrimp.gemspec &&\
    gem install scrimp-1.0.0.gem

RUN mkdir /project

WORKDIR /project

EXPOSE 7000

CMD [ "/usr/local/bin/scrimp", "/project/src" ]