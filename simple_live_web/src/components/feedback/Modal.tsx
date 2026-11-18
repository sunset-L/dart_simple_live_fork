import type React from "react";
import { Modal as AntModal } from "antd";

export function Modal({
  title,
  onClose,
  children,
}: {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
}) {
  return (
    <AntModal
      open
      title={title}
      onCancel={onClose}
      footer={null}
      width={420}
      destroyOnHidden
    >
      {children}
    </AntModal>
  );
}
