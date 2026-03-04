locals {
  source_hash = md5(join("", [
    for f in fileset(var.source_dir, "**") : filemd5("${var.source_dir}/${f}")
  ]))
}

data "archive_file" "default" {
  type        = "zip"
  output_path = "/tmp/${var.name}/function-source.zip"
  source_dir  = var.source_dir
}

resource "google_storage_bucket_object" "default" {
  name   = format("%s/%s-%s.zip", var.name, "function-source", local.source_hash)
  bucket = var.bucket_name
  source = data.archive_file.default.output_path
  source_md5hash = local.source_hash
  lifecycle {
    ignore_changes = [
      generation,
      crc32c,
      md5hash
    ]
  }
}

resource "google_cloudfunctions2_function" "default" {
  name        = var.name
  project     = var.project_id
  location    = var.location
  description = var.description

  build_config {
    runtime     = var.runtime
    entry_point = var.entry_point
    source {
      storage_source {
        bucket = var.bucket_name
        object = google_storage_bucket_object.default.name
      }
    }
    service_account = var.build_service_account
  }

  service_config {
    max_instance_count             = coalesce(var.max_instance_count, 1)
    min_instance_count             = var.min_instance_count
    available_memory               = coalesce(var.available_memory, "256M")
    timeout_seconds                = coalesce(var.timeout, 540)
    ingress_settings               = coalesce(var.ingress_settings, "ALLOW_INTERNAL_ONLY")
    all_traffic_on_latest_revision = true
    service_account_email          = var.service_account_email
    environment_variables          = var.environment_variables
  }

  labels = var.function_labels

  lifecycle {
    ignore_changes = [build_config[0].docker_repository]
  }
}

resource "google_pubsub_subscription" "default" {
  name                 = "${var.name}-subscription"
  topic                = var.pubsub_topic
  project              = var.project_id
  ack_deadline_seconds = 600
  filter               = "attributes.${var.pubsub_filter.attribute} = \"${var.pubsub_filter.value}\""

  push_config {
    push_endpoint = google_cloudfunctions2_function.default.service_config[0].uri
    oidc_token {
      service_account_email = var.trigger_service_account_email
    }
  }
}
