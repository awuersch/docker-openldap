import os
import sys
import time
from threading import Event

import ldap3
import etcd3

LEADER_KEY = 'leader'
LEASE_TTL = 5
SLEEP = 1


def put_not_exist(client, key, value, lease=None):
    status, _ = client.transaction(
        compare=[
            client.transactions.version(key) == 0
        ],
        success=[
            client.transactions.put(key, value, lease)
        ],
        failure=[],
    )
    return status


def leader_election(client, me, leader_key):
    try:
        lease = client.lease(LEASE_TTL)
        status = put_not_exist(client, leader_key, me, lease)
    except Exception:
        status = False
    return status, lease


def pr_conn_usage(o):
    print('Messages transmitted:', str(o.messages_transmitted))
    print('Messages received:', str(o.messages_received))
    print('Bytes transmitted:', str(o.bytes_transmitted))
    print('Bytes received:', str(o.bytes_received))
    print('Bind operations:', str(o.bind_operations))
    print('Search operations:', str(o.search_operations))
    print('Unbind operations:', str(o.unbind_operations))


def bind_bool(c):
    try:
        result = c.bind()
    except (TimeoutError):
        print('timeout')
        result = False
    except (Exception):
        result = False
    return result


def main(ldap_server_name, ldap_domain, etcd_server_name):
    ldap_server = ldap3.Server(ldap_server_name, get_info=ldap3.ALL)
    waiting_sleep_interval = 4
    checking_sleep_interval = 2
    ldap_conn = ldap3.Connection(ldap_server,
                                 collect_usage=True,
                                 receive_timeout=checking_sleep_interval)

    etcd_client = etcd3.client(host=etcd_server_name, port=2379, timeout=2)
    leader_key = ldap_domain + '/' + LEADER_KEY

    print('starting')

    while True:
        print('binding')
        while not bind_bool(ldap_conn):
            print('waiting for bind', ldap_conn.result)
            time.sleep(waiting_sleep_interval)
            print('waiter waking up')

        while True:
            print('electing')
            leader, lease = leader_election(etcd_client,
                                            ldap_server_name,
                                            leader_key)

            if leader:
                print('leader')

                try:
                    while bind_bool(ldap_conn):
                        ldap_conn.unbind()
                        print('refreshing lease')
                        lease.refresh()
                        time.sleep(checking_sleep_interval)
                        print('leader waking up')
                    print('leader bind check failed', ldap_conn.result)
                    ldap_conn.unbind()
                    break
                except (Exception, KeyboardInterrupt):
                    return
                finally:
                    print('revoking lease')
                    lease.revoke()
            else:
                print('follower; standby')

                election_event = Event()

                def watch_cb(event):
                    if isinstance(event, etcd3.events.DeleteEvent):
                        election_event.set()
                watch_id = etcd_client.add_watch_callback(leader_key, watch_cb)

                try:
                    while not election_event.is_set():
                        time.sleep(checking_sleep_interval)

                    print('follower checking bind')
                    if bind_bool(ldap_conn):
                        print('follower bound')
                        ldap_conn.unbind()
                    else:
                        print('follower bind check failed', ldap_conn.result)
                        ldap_conn.unbind()
                        break
                    print('new election')
                except (Exception, KeyboardInterrupt):
                    return
                finally:
                    print('cancelling watch')
                    etcd_client.cancel_watch(watch_id)


if __name__ == '__main__':
    ldap_server_name = sys.argv[1]
    ldap_domain = sys.argv[2]
    etcd_server_name = sys.argv[3]
    main(ldap_server_name, ldap_domain, etcd_server_name)
