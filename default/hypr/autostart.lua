local startup_steps = {
  o.import_environment_command(),
  "dbus-update-activation-environment --systemd --all",
  { "omarchy-launch-shell", detached = true },
  "omarchy-powerprofiles-init",
  { o.launch("omarchy-hyprland-monitor-watch"), detached = true },
  { o.launch("udiskie --automount --no-notify --no-tray"), detached = true },
  "sleep 2 && omarchy-hook post-boot",
}

for _, step in ipairs(startup_steps) do
  if type(step) == "table" then
    o.on_start_detached(step[1])
  else
    o.on_start(step)
  end
end

o.dispatch_startup()
