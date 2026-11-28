# gVisor (runsc) as an extra containerd runtime, so tenant pods can run in a
# user-space kernel: cloud-argo's RuntimeClass `gvisor` (handler runsc) and
# its admission policies force it for every namespace labelled
# 2143.me/tenant. Platform pods keep runc.
#
# k3s renders containerd's config from this template; `template "base"` keeps
# the stock k3s config and only appends the runtime (docs.k3s.io/advanced,
# "Base template"), so nothing k3s generates is copied here. All three nodes
# get it, so the config is identical even though tenants never run on
# plat-home.
{pkgs, ...}: {
  # containerd runs as a child of k3s and finds containerd-shim-runsc-v1 (and
  # the shim finds runsc) on the k3s service's PATH.
  systemd.services.k3s.path = [pkgs.gvisor];
  environment.systemPackages = [pkgs.gvisor];

  services.k3s.containerdConfigTemplateV3 = ''
    {{ template "base" . }}

    [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runsc]
      runtime_type = "io.containerd.runsc.v1"
  '';
}
