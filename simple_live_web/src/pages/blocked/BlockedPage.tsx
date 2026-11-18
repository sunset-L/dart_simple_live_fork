import { useState } from "react";
import { Shield, Plus, X } from "lucide-react";
import type { Library } from "../../services/libraryData";

export function Blocked({
  data,
  commit,
  notify,
}: {
  data: Library;
  commit: (data: Library) => void;
  notify: (message: string) => void;
}) {
  const [value, setValue] = useState("");
  function update(words: string[]) {
    try {
      commit({ ...data, blocked: words });
      setValue("");
    } catch (error) {
      notify(error instanceof Error ? error.message : "保存失败");
    }
  }
  function add() {
    if (value.trim()) update([...new Set([...data.blocked, value.trim()])]);
  }
  return (
    <div className="settings-content">
      <div className="section-heading">
        <h2>弹幕屏蔽词</h2>
        <Shield size={28} className="accent" />
      </div>
      <form
        className="blocked-add"
        onSubmit={(event) => {
          event.preventDefault();
          add();
        }}
      >
        <input
          aria-label="屏蔽词"
          value={value}
          onChange={(event) => setValue(event.target.value)}
          maxLength={100}
          placeholder="添加屏蔽词"
        />
        <button className="primary" disabled={!value.trim()}>
          <Plus size={17} />
          添加
        </button>
      </form>
      <div className="word-list">
        {data.blocked.map((word) => (
          <span key={word}>
            {word}
            <button
              title={`移除 ${word}`}
              aria-label={`移除 ${word}`}
              onClick={() =>
                update(data.blocked.filter((item) => item !== word))
              }
            >
              <X size={13} />
            </button>
          </span>
        ))}
      </div>
    </div>
  );
}
