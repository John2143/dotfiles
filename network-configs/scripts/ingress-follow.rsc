# ingress-follow - RouterOS script source (not an /export). Installed as
# /system script "ingress-follow"; run every minute by the test-script of
# /tool netwatch "ingress-follow" (device-mode home blocks /system scheduler).
# Points WAN 80/443 at the cluster ingress VIP: john2143.com -> router DNS ->
# lan-dns -> k8s_gateway -> Gateway address -> Traefik VIP. Answers outside
# 192.168.6.0/24 (resolve failure, or lan-dns down so the router saw the public
# answer) keep the current target. Install/verify: argo docs/2026-10-15-fungible-ingress.md.
:local ok false
:local ip
:do { :set ip [:resolve "john2143.com"]; :set ok true } on-error={}
:if (!$ok) do={
  :log warning "ingress-follow: cannot resolve john2143.com; keeping current dst-nat target"
} else={
  :if (!($ip in 192.168.6.0/24)) do={
    :log warning ("ingress-follow: john2143.com resolved to " . $ip . " (outside 192.168.6.0/24); keeping current dst-nat target")
  } else={
    :foreach c in={"ingress http (tcp/80) -> traefik VIP (ingress-follow)";"ingress https (tcp/443) -> traefik VIP (ingress-follow)"} do={
      :local ids [/ip firewall nat find comment=$c]
      :if ([:len $ids] != 1) do={
        :log error ("ingress-follow: expected 1 nat rule with comment '" . $c . "', found " . [:len $ids])
      } else={
        :local cur [/ip firewall nat get ($ids->0) to-addresses]
        :if ($cur != [:tostr $ip]) do={
          /ip firewall nat set ($ids->0) to-addresses=$ip
          :log warning ("ingress-follow: " . $c . " " . $cur . " -> " . $ip)
        }
      }
    }
  }
}
