import sys
import time
from threading import Event
import queue

import ldap3
import etcd3

LEADER_KEY = 'leader'
LEASE_TTL = 5
SLEEP = 1


def bind_bool(c):
    try:
        result = c.bind()
    except (TimeoutError):
        print('bind timeout')
        result = False
    except (Exception):
        result = False
    return result


def modify_bool(server_name, conn, dn, url):
    result = False
    try:
        cmd = (ldap3.MODIFY_REPLACE, [url])
        print("updating")
        if conn.modify(dn, {'olcUpdateRef': [cmd]}):
            print("server", server_name, "updated")
            result = True
        else:
            print("server", server_name, "update failed:", conn.result)
    except (TimeoutError):
        print('modify timeout')
        result = False
    except (Exception):
        result = False
    return result


def update_server(user, password, update_ref, server_name):
    update_ref_dn = "olcDatabase={1}mdb,cn=config"
    update_ref_str = str(update_ref, "utf-8")
    update_ref_url = b'ldap://' + update_ref

    server = ldap3.Server(server_name, get_info=None, connect_timeout=2)
    conn = ldap3.Connection(server,
                            user=username,
                            password=password,
                            authentication=ldap3.SIMPLE,
                            auto_referrals=False)
    result = False
    if bind_bool(conn):
        result = modify_bool(server_name, conn, update_ref_dn, update_ref_url)
        conn.unbind()
    else:
        print("server", server_name, "bind failed:", conn.result)
    return result


def set_update_ref(user, password, update_ref, server_names):
    print("setting update_ref url", str(update_ref_url, "utf-8"))
    # update with retries if failure
    max_retries = 3
    for i in [1:max_retries]:
        server_names = [
            server_name
            for server_name in server_names
            if not update_server(user, password, update_ref, server_name)]
        if not server_names:
            break
        else:
            print("updates incomplete.", max_retries-i, "retries left")
            time.sleep(3)
    if not server_names:
        print("retries failed; a replica may be inaccessible")


def main(domain, etcd_server_name, username, password, server_names):
    print('starting')
    client = etcd3.client(host=etcd_server_name, port=2379)
    leader_key = domain + '/' + LEADER_KEY

    update_ref, _ = client.get(leader_key)
    print("etcd key", leader_key, "=", str(update_ref, "utf-8"))
    set_update_ref(username, password, update_ref, server_names)

    put_event = Event()
    event_queue = queue.Queue()

    def watch_cb(event):
        if isinstance(event, etcd3.events.PutEvent):
            put_event.set()
            event_queue.put(event.value)

    watch_id = client.add_watch_callback(leader_key, watch_cb)
    print('watching')

    while True:
        while not put_event.is_set():
            time.sleep(2)

        print('got a put event')
        put_event.clear()

        new_update_ref = update_ref
        while not event_queue.empty():
            new_update_ref = event_queue.get()

        if new_update_ref != update_ref:
            update_ref = new_update_ref
            print("new etcd key", leader_key, "=", str(update_ref, "utf-8"))
            set_update_ref(username, password, update_ref, server_names)


if __name__ == '__main__':
    domain = sys.argv[1]
    etcd_server_name = sys.argv[2]
    username = sys.argv[3]
    password = sys.argv[4]
    server_names = sys.argv[5-len(sys.argv):]
    main(domain, etcd_server_name, username, password, server_names)
