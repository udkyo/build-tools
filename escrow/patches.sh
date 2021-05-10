# This file should contain any runtime patches that are applied during in-container-build

patch_md5s() {
  if ls /home/couchbase/.cbdepscache/*.md5 1> /dev/null 2>&1
  then
    for f in /home/couchbase/.cbdepscache/*.md5
    do
        if [[ "$f" != *"tgz"* ]]
        then
            echo $f
            fixedname="$(echo $f | sed 's/\(.*\.\)md5/\1tgz.md5/')"
            rm -f "$fixedname"
            cp "$f" "$fixedname"
        fi
    done
  fi
}

patch_suse15_deps() {
  if [ "$RELEASE" = "mad-hatter" ]
  then
    if ls /home/couchbase/.cbdepscache/*suse15.0* 1> /dev/null 2>&1
    then
      for f in /home/couchbase/.cbdepscache/*suse15.0*
      do
        fixedname="$(echo $f | sed 's/suse15\.0/suse15/')"
        cp "$f" "$fixedname"
      done
    fi
  fi
}
