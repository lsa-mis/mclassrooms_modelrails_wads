module LifecycleHelper
  # Sole legal display path for lifecycle state. Never render
  # `record.status.to_s` (titleized or otherwise) — that would leak the
  # internal words "Suspended"/"Discarded" into UI the vocabulary rule
  # reserves for "Locked"/"Deleted".
  def lifecycle_status_label(record)
    t("lifecycle_status.#{record.status}")
  end

  # The badge form of the label, for the operations pages: one treatment
  # wherever a status shows. aria-label because "Locked" alone says nothing
  # about what it is the status of; warning tint for a lock only — the state
  # an operator acts on.
  def lifecycle_status_badge(record, **attrs)
    label = lifecycle_status_label(record)
    ui :badge, label, variant: :soft, tone: (record.suspended? ? :warning : :neutral),
       "aria-label": "#{t('lifecycle_status.prefix')}: #{label}", **attrs
  end
end
