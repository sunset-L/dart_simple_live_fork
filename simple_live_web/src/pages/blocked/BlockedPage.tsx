import { useState } from "react";
import { Shield, Plus } from "lucide-react";
import { Button, Input, Tag } from "antd";
import type { Library } from "../../services/libraryData";

export function Blocked({
  data,
  commit,
  notify,
}: {
  data: Library;
  commit: (data: Library) => Promise<void>;
  notify: (message: string) => void;
}) {
  const [value, setValue] = useState("");
  async function update(words: string[]) {
    try {
      await commit({ ...data, blocked: words });
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
        <Input
          aria-label="屏蔽词"
          value={value}
          onChange={(event) => setValue(event.target.value)}
          maxLength={100}
          placeholder="添加屏蔽词"
        />
        <Button
          type="primary"
          htmlType="submit"
          disabled={!value.trim()}
          icon={<Plus size={17} />}
        >
          添加
        </Button>
      </form>
      <div className="word-list">
        {data.blocked.map((word) => (
          <Tag
            key={word}
            closable
            onClose={(event) => {
              event.preventDefault();
              void update(data.blocked.filter((item) => item !== word));
            }}
          >
            {word}
          </Tag>
        ))}
      </div>
    </div>
  );
}
