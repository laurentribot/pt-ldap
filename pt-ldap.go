package main

import (
    "os"
	"os/exec"
	"strings"
)

func main() {

    if len(os.Args) == 1 {

        os.Mkdir("/var/run/saslauthd", 0750)
        saslauthd := exec.Command("/usr/sbin/saslauthd", "-a", "ldap", "-m", "/var/run/saslauthd", "-O", "/etc/saslauthd.conf")
        saslauthd.Stdout = os.Stdout
        saslauthd.Stderr = os.Stderr
        saslauthd.Start()

        if _, err := os.Stat("/etc/openldap/slapd.d"); os.IsNotExist(err) {
            os.Mkdir("/etc/openldap/slapd.d", 0750)
            init := exec.Command("/usr/sbin/slapadd", "-n", "0", "-F", "/etc/openldap/slapd.d", "-l", "/etc/openldap/slapd.ldif")
            init.Start()
        }
        hostname, _ := os.Hostname()
        slapd := exec.Command("/usr/sbin/slapd", "-h", "ldap://" + hostname + " ldaps://" + hostname + " ldapi:///", "-F", "/etc/openldap/slapd.d", "-d", "0")
        slapd.Stdout = os.Stdout
        slapd.Stderr = os.Stderr
        slapd.Run()

    } else {
        cmd := exec.Command(strings.Join(os.Args[1:1], ""), os.Args[2:]...)
        cmd.Stdout = os.Stdout
        cmd.Stderr = os.Stderr
        cmd.Run()
    }
}
