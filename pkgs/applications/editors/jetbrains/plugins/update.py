#! /usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 python3.pkgs.requests nix

from json import load, dump
from pathlib import Path
from requests import get
from subprocess import run
from argparse import ArgumentParser

PLUGINS_FILE = Path(__file__).parent.joinpath("plugins.json").resolve()


def update_all():
    plugins = load(open(PLUGINS_FILE))
    total = len(plugins)
    updated = 0
    result = {}
    for id_, current in plugins.items():

        if "-" in id_:
            int_id, channel = id_.split("-", 1)
        else:
            channel = ""
            int_id = id_

        latest = latest_info(int_id, channel)
        updated_hash = None
        if int(latest["version"]) > int(current["version"]):
            updated_hash = get_hash(latest["url"])
            print(f'Updated {current["name"]} from {current["version"]} to {latest["version"]}')
            updated += 1
        result[id_] = {
            "url": latest["url"],
            "hash": updated_hash or current["hash"],
            "name": current["name"],
            "version": latest["version"]
        }

    dump(sort(result), open(PLUGINS_FILE, "w"), indent=2)
    print(f"\n{updated}/{total} plugins updated")


def get_hash(url):
    args = ["nix-prefetch-url", url, "--print-path"]
    if url.endswith(".zip"):
        args.append("--unpack")
    else:
        args.append("--executable")
    path_process = run(args, capture_output=True)
    path = path_process.stdout.decode().split("\n")[1]
    result = run(["nix", "hash", "path", path], capture_output=True)
    return result.stdout.decode()[:-1]


def latest_info(id_, channel=""):
    url = f"https://plugins.jetbrains.com/api/plugins/{id_}/updates?channel={channel}"
    resp = get(url)
    decoded = resp.json()

    if resp.status_code != 200:
        print("Error from server: " + decoded["message"])
        exit(1)

    return {
        "version": decoded[0]["id"],
        "url": "https://plugins.jetbrains.com/files/" + decoded[0]["file"]
    }


def get_name(id_):
    url = f"https://plugins.jetbrains.com/api/plugins/{id_}"
    response = get(url).json()
    return response["link"].split("-", 1)[1]


def add_plugin(id_, channel=""):
    id_ = str(id_)
    channel_ext = ""
    if channel != "":
        channel_ext = "-" + channel

    plugins = load(open(PLUGINS_FILE))
    if id_+channel_ext in plugins:
        print(f"{plugins[id_+channel_ext]['name']} already exists!")
        return

    info = latest_info(id_, channel)

    name = get_name(id_)

    plugins[id_+channel_ext] = {
        "url": info["url"],
        "hash": get_hash(info["url"]),
        "name": name+channel_ext,
        "version": info["version"]
    }

    print(f"Added {name}" +
          ("-"+channel if channel else ""))

    dump(sort(plugins), open(PLUGINS_FILE, "w"), indent=2)


def sort(dict_):
    return {key: val for key, val in sorted(dict_.items(), key=lambda x: int(x[0].split("-")[0]))}


def check_plugin(id_, channel):
    id_ = str(id_)
    channel_ext = ""
    if channel != "":
        channel_ext = "-" + channel

    plugins = load(open(PLUGINS_FILE))

    if id_+channel_ext not in plugins:
        print("Cannot check nonexistent plugin!")
        exit(1)

    old_info = plugins[id_+channel_ext]

    info = latest_info(id_, channel)
    name = get_name(id_)
    new_info = {
        "url": info["url"],
        "hash": get_hash(info["url"]),
        "name": name + channel_ext,
        "version": info["version"]
    }

    valid = True
    for (key, new), old in zip(new_info.items(), old_info.values()):
        if new != old:
            print(f"{key} mismatch, old is {old}, new is {new}")
            valid = False
    if valid:
        print("Plugin is ok")


def main():
    parser = ArgumentParser()
    sub = parser.add_subparsers(dest="action")

    sub.add_parser("update")

    new = sub.add_parser("new")
    new.add_argument("id", type=int)
    new.add_argument("channel", nargs="?", default="")

    bulk = sub.add_parser("bulk")
    bulk.add_argument("id", type=int, nargs="+")

    check = sub.add_parser("check")
    check.add_argument("id", type=int)
    check.add_argument("channel", nargs="?", default="")

    args = parser.parse_args()
    if args.action == "new":
        add_plugin(args.id, args.channel)
    elif args.action == "bulk":
        for plugin in args.id:
            add_plugin(plugin)
    elif args.action == "check":
        check_plugin(args.id, args.channel)
    else:
        update_all()


if __name__ == '__main__':
    main()
