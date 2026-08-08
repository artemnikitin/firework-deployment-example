# The control and data planes remain separate VPCs, but the data plane needs a
# private route to the internal registry load balancer. Both peering directions
# are managed here so the independently-applied control-plane stack does not
# need to read data-plane state.

resource "google_compute_network_peering" "data_to_control" {
  count = local.effective_control_plane_network_self_link != "" ? 1 : 0

  name                 = "${local.name_prefix}-to-control-plane"
  network              = google_compute_network.data_plane.self_link
  peer_network         = local.effective_control_plane_network_self_link
  export_custom_routes = true
  import_custom_routes = true
}

resource "google_compute_network_peering" "control_to_data" {
  count = local.effective_control_plane_network_self_link != "" ? 1 : 0

  name                 = "${local.controlplane_name_prefix}-to-data-plane"
  network              = local.effective_control_plane_network_self_link
  peer_network         = google_compute_network.data_plane.self_link
  export_custom_routes = true
  import_custom_routes = true

  depends_on = [google_compute_network_peering.data_to_control]
}
