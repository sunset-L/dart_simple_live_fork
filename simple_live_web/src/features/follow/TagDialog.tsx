import { useState } from "react";
import { Check } from "lucide-react";
import { AutoComplete, Button } from "antd";
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
        <AutoComplete
          autoFocus
          aria-label="标签名称"
          value={name}
          onChange={(value) => setName(value.slice(0, 40))}
          options={[...new Set(["全部", ...tags])].map((value) => ({ value }))}
          style={{ width: "100%" }}
          maxLength={40}
          filterOption={(input, option) =>
            String(option?.value).includes(input)
          }
        />
        <div className="modal-actions">
          <Button onClick={onClose}>取消</Button>
          <Button
            type="primary"
            htmlType="submit"
            disabled={!name.trim()}
            icon={<Check size={16} />}
          >
            保存
          </Button>
        </div>
      </form>
    </Modal>
  );
}
