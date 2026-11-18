import { Component, type ErrorInfo, type ReactNode } from "react";
import { RefreshCw } from "lucide-react";
import { Button } from "antd";

export class PlayerBoundary extends Component<
  { children: ReactNode },
  { failed: boolean; version: number; error: string }
> {
  state = { failed: false, version: 0, error: "" };

  static getDerivedStateFromError(error: Error) {
    return { failed: true, error: error.message };
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error("Player initialization failed", error, info.componentStack);
  }

  render() {
    if (this.state.failed)
      return (
        <div className="player-error" role="alert">
          <strong>播放器加载失败</strong>
          <span className="player-error-detail">{this.state.error}</span>
          <Button
            type="primary"
            icon={<RefreshCw size={16} />}
            onClick={() =>
              this.setState((state) => ({
                failed: false,
                error: "",
                version: state.version + 1,
              }))
            }
          >
            重新加载播放器
          </Button>
        </div>
      );
    return (
      <div key={this.state.version} className="player-boundary">
        {this.props.children}
      </div>
    );
  }
}
