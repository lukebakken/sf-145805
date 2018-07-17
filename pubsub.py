import collections
import datetime
import pika
import pprint
import socket
import time

PubSub = collections.namedtuple('PubSub', ['conn', 'pub_chan', 'sub_chan', 'queue_name'])

def new_conn():
    conn_params = pika.ConnectionParameters(host='localhost',port=55672)
    conn = None
    while conn is None:
        try:
            conn = pika.BlockingConnection(conn_params)
        except pika.exceptions.ConnectionClosed:
            if conn is not None:
                conn.close()
            conn = None
            print('[ERROR] could not open connection, re-trying in 5 seconds')
            time.sleep(5)
    pub_chan = conn.channel()
    queue_name = pub_chan.queue_declare(exclusive=True).method.queue
    sub_chan = conn.channel()
    return PubSub(conn, pub_chan, sub_chan, queue_name)

def publish_msg(ps):
    msg_props = pika.BasicProperties(content_type='text/plain')
    msg = 'HAI {} at {}'.format(ps.queue_name, str(datetime.datetime.now()))
    published = False
    while published is False:
        try:
            ps.pub_chan.basic_publish('', ps.queue_name, msg, msg_props)
            print('[INFO] published msg: {}'.format(msg))
            published = True
        except pika.exceptions.ConnectionClosed:
            print('[ERROR] publisher connection closed, re-opening')
            ps = new_conn()
    return ps

def get_msg(ps):
    consumed = False
    while consumed is False:
        try:
            (method, properties, body) = ps.sub_chan.basic_get(ps.queue_name, no_ack=True)
            consumed = True
        except pika.exceptions.ConnectionClosed:
            print('[ERROR] consumer connection closed, re-opening')
            ps = new_conn()
    print('[INFO] consumed msg method: ')
    pprint.pprint(method)
    print('[INFO] consumed msg properties: ')
    pprint.pprint(properties)
    print('[INFO] consumed msg body: ')
    pprint.pprint(body)
    return ps

pubsub = new_conn()

try:
    while True:
        pubsub = publish_msg(pubsub)
        time.sleep(1)
        pubsub = get_msg(pubsub)
except KeyboardInterrupt:
    pubsub.pub_chan.close()
    pubsub.sub_chan.close()
    pubsub.conn.close()
