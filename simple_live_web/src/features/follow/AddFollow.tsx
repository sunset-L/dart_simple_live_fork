import { useState } from "react";
import { Plus } from "lucide-react";
import { Modal } from "../../components/feedback/Modal";
import { platforms, type Follow } from "../../services/libraryData";

export function AddFollow({
  onClose,
  onSave,
}: {
  onClose: () => void;
  onSave: (user: Follow) => void;
}) {
  const [siteId, setSite] = useState("bilibili");
  const [roomId, setRoom] = useState("");
  const [userName, setName] = useState("");
  return (
    <Modal title="添加关注" onClose={onClose}>
      <form
        onSubmit={(event) => {
          event.preventDefault();
          const id = roomId.trim();
          if (!id || !userName.trim()) return;
          onSave({
            id: `${siteId}_${id}`,
            roomId: id,
            siteId,
            userName: userName.trim(),
            face: "",
            addTime: new Date().toISOString(),
            tag: "全部",
          });
        }}
      >
        <label className="field">
          直播平台
          <select
            value={siteId}
            onChange={(event) => setSite(event.target.value)}
          >
            {platforms.map((site) => (
              <option key={site.id} value={site.id}>
                {site.name}
              </option>
            ))}
          </select>
        </label>
        <label className="field">
          房间号
          <input
            required
            maxLength={100}
            pattern="[A-Za-z0-9_-]+"
            value={roomId}
            onChange={(event) => setRoom(event.target.value)}
          />
        </label>
        <label className="field">
          主播名称
          <input
            required
            maxLength={100}
            value={userName}
            onChange={(event) => setName(event.target.value)}
          />
        </label>
        <div className="modal-actions">
          <button type="button" onClick={onClose}>
            取消
          </button>
          <button className="primary">
            <Plus size={16} />
            添加
          </button>
        </div>
      </form>
    </Modal>
  );
}
