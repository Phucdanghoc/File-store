FROM rabbitmq:3.12-management
COPY rabbitmq.conf /etc/rabbitmq/
RUN rabbitmq-plugins enable rabbitmq_shovel rabbitmq_shovel_management
EXPOSE 15672
EXPOSE 5672