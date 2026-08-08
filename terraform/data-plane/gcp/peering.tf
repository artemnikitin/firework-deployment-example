# The control and data planes remain separate VPCs, but the data plane needs a
# private route to the internal registry load balancer. Both peering directions
# are managed here so the control-plane stack does not need to read data-plane
# state. The data-plane VPC owns the lifecycle of this cross-stack peering.

resource "google_compute_network_peering" "data_to_control" {
  count = local.effective_control_plane_network_self_link != "" ? 1 : 0

  name         = "${local.name_prefix}-to-control-${local.peering_name_suffix}"
  network      = google_compute_network.data_plane.self_link
  peer_network = local.effective_control_plane_network_self_link
}

resource "google_compute_network_peering" "control_to_data" {
  count = local.effective_control_plane_network_self_link != "" ? 1 : 0

  name         = "${local.controlplane_name_prefix}-to-data-${local.peering_name_suffix}"
  network      = local.effective_control_plane_network_self_link
  peer_network = google_compute_network.data_plane.self_link

  depends_on = [google_compute_network_peering.data_to_control]
}
