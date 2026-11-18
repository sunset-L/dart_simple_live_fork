import { useState } from "react";
import { Check } from "lucide-react";
import { Modal } from "../../components/feedback/Modal";
import type { Follow } from "../../services/libraryData";

export function TagDialog({
  value,
  tags,
  onClose,
  onSave,
}: {
  value: Follow;
  tags: string[];
  onClose: () => void;
  onSave: (name: string) => void;
}) {
  const [name, setName] = useState(value.tag);
  return (
    <Modal title="设置标签" onClose={onClose}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          if (name.trim()) onSave(name.trim());
        }}
      >
        <input
          autoFocus
          aria-label="标签名称"
          value={name}
          onChange={(event) => setName(event.target.value)}
          list="tag-options"
          maxLength={40}
        />
        <datalist id="tag-options">
          {[...new Set(["全部", ...tags])].map((tag) => (
            <option key={tag} value={tag} />
          ))}
        </datalist>
        <div className="modal-actions">
          <button type="button" onClick={onClose}>
            取消
          </button>
          <button className="primary" disabled={!name.trim()}>
            <Check size={16} />
            保存
          </button>
        </div>
      </form>
    </Modal>
  );
}
