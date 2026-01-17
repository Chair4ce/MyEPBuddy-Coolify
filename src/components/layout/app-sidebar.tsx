"use client";

import { useState, useEffect, useCallback } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import { ScrollArea } from "@/components/ui/scroll-area";
import { Separator } from "@/components/ui/separator";
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
  TooltipProvider,
} from "@/components/ui/tooltip";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import {
  LayoutDashboard,
  FileText,
  Users,
  Sparkles,
  Settings,
  Key,
  Shield,
  Menu,
  X,
  Library,
  Wand2,
  Heart,
  Award,
  Loader2,
  PanelLeftClose,
  PanelLeft,
  PanelLeftOpen,
  Check,
} from "lucide-react";
import { AppLogo } from "@/components/layout/app-logo";
import type { Profile } from "@/types/database";

interface AppSidebarProps {
  profile: Profile | null;
}

// Sidebar mode types
type SidebarMode = "pinned-open" | "hover-expand" | "pinned-closed";

const SIDEBAR_STORAGE_KEY = "sidebar-mode";

const navItems = [
  {
    title: "Dashboard",
    href: "/dashboard",
    icon: LayoutDashboard,
    roles: ["member", "admin"],
  },
  {
    title: "My Performance",
    href: "/entries",
    icon: FileText,
    roles: ["member", "admin"],
  },
  {
    title: "My Team",
    href: "/team",
    icon: Users,
    roles: ["member", "admin"],
  },
  {
    title: "Generate EPB",
    href: "/generate",
    icon: Sparkles,
    roles: ["member", "admin"],
  },
  {
    title: "Generate Award",
    href: "/award",
    icon: Award,
    roles: ["member", "admin"],
  },
  {
    title: "Statement Library",
    href: "/library",
    icon: Library,
    roles: ["member", "admin"],
  },
];

const settingsItems = [
  {
    title: "Profile",
    href: "/settings",
    icon: Settings,
    roles: ["member", "admin"],
  },
  {
    title: "LLM Settings",
    href: "/settings/llm",
    icon: Wand2,
    roles: ["member", "admin"],
  },
  {
    title: "API Keys",
    href: "/settings/api-keys",
    icon: Key,
    roles: ["member", "admin"],
  },
  {
    title: "Admin Config",
    href: "/admin/config",
    icon: Shield,
    roles: ["admin"],
  },
];

// NavItem component with tooltip support for collapsed state
function NavItem({
  item,
  isActive,
  isLoading,
  isCollapsed,
  onClick,
}: {
  item: (typeof navItems)[0];
  isActive: boolean;
  isLoading: boolean;
  isCollapsed: boolean;
  onClick: () => void;
}) {
  const content = (
    <Link
      href={item.href}
      onClick={onClick}
      className={cn(
        // Base styles - consistent height for both states
        "flex items-center h-10 rounded-md text-sm font-medium transition-colors",
        // Width and alignment based on collapsed state
        isCollapsed 
          ? "w-10 justify-center" 
          : "w-full px-3 gap-3",
        isActive
          ? "bg-sidebar-accent text-sidebar-accent-foreground"
          : "text-sidebar-foreground hover:bg-sidebar-accent/50"
      )}
      aria-label={item.title}
    >
      {isLoading ? (
        <Loader2 className="size-4 shrink-0 animate-spin" />
      ) : (
        <item.icon className="size-4 shrink-0" />
      )}
      {!isCollapsed && (
        <span className="whitespace-nowrap">
          {item.title}
        </span>
      )}
    </Link>
  );

  if (isCollapsed) {
    return (
      <Tooltip>
        <TooltipTrigger asChild>{content}</TooltipTrigger>
        <TooltipContent side="right" sideOffset={8}>
          {item.title}
        </TooltipContent>
      </Tooltip>
    );
  }

  return content;
}

export function AppSidebar({ profile }: AppSidebarProps) {
  const pathname = usePathname();
  const [mobileOpen, setMobileOpen] = useState(false);
  const [loadingHref, setLoadingHref] = useState<string | null>(null);
  const [mode, setMode] = useState<SidebarMode>("pinned-open");
  const [isHovered, setIsHovered] = useState(false);
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [isInitialized, setIsInitialized] = useState(false);
  const userRole = profile?.role || "subordinate";

  // Load saved mode from localStorage on mount
  useEffect(() => {
    const savedMode = localStorage.getItem(SIDEBAR_STORAGE_KEY) as SidebarMode;
    if (savedMode && ["pinned-open", "hover-expand", "pinned-closed"].includes(savedMode)) {
      setMode(savedMode);
    }
    setIsInitialized(true);
  }, []);

  // Save mode to localStorage when changed
  useEffect(() => {
    if (isInitialized) {
      localStorage.setItem(SIDEBAR_STORAGE_KEY, mode);
    }
  }, [mode, isInitialized]);

  // Clear loading state when navigation completes
  useEffect(() => {
    setLoadingHref(null);
  }, [pathname]);

  const handleNavClick = useCallback((href: string) => {
    if (href !== pathname) {
      setLoadingHref(href);
    }
    setMobileOpen(false);
  }, [pathname]);

  const handleModeChange = useCallback((newMode: SidebarMode) => {
    setMode(newMode);
  }, []);

  // Determine if sidebar is visually collapsed
  // In hover-expand mode: collapsed when not hovered (unless menu is open)
  // Keep expanded if dropdown menu is open to allow mouse movement to menu items
  const isCollapsed = mode === "pinned-closed" || (mode === "hover-expand" && !isHovered && !isMenuOpen);
  const isExpanded = mode === "pinned-open" || (mode === "hover-expand" && (isHovered || isMenuOpen));

  // Only push content when pinned open - hover and closed modes overlay
  const shouldPushContent = mode === "pinned-open";

  const filteredNavItems = navItems.filter((item) =>
    item.roles.includes(userRole)
  );
  const filteredSettingsItems = settingsItems.filter((item) =>
    item.roles.includes(userRole)
  );

  // Get the icon for current mode
  const getModeIcon = () => {
    switch (mode) {
      case "pinned-open":
        return PanelLeft;
      case "hover-expand":
        return PanelLeftOpen;
      case "pinned-closed":
        return PanelLeftClose;
    }
  };

  const ModeIcon = getModeIcon();

  return (
    <TooltipProvider delayDuration={0}>
      {/* Mobile hamburger button */}
      {!mobileOpen && (
        <Button
          variant="ghost"
          size="icon"
          className="fixed top-4 left-4 z-50 lg:hidden"
          onClick={() => setMobileOpen(true)}
          aria-label="Open menu"
        >
          <Menu className="size-5" />
        </Button>
      )}

      {/* Mobile overlay */}
      {mobileOpen && (
        <div
          className="fixed inset-0 bg-black/50 z-40 lg:hidden"
          onClick={() => setMobileOpen(false)}
        />
      )}

      {/* Desktop sidebar spacer - only reserves space when pinned open */}
      <div
        className={cn(
          "hidden lg:block shrink-0 transition-all duration-150 ease-out",
          shouldPushContent ? "w-64" : "w-16"
        )}
        aria-hidden="true"
      />

      {/* Sidebar */}
      <aside
        onMouseEnter={() => setIsHovered(true)}
        onMouseLeave={() => setIsHovered(false)}
        className={cn(
          "fixed top-0 left-0 z-40 h-full bg-sidebar border-r border-sidebar-border transition-all duration-150 ease-out",
          // Mobile positioning
          "lg:translate-x-0",
          mobileOpen ? "translate-x-0 w-64" : "-translate-x-full",
          // Desktop width based on expanded state
          "lg:block",
          isExpanded ? "lg:w-64" : "lg:w-16",
          // Add shadow when overlapping content (hover-expand mode when hovered)
          mode === "hover-expand" && isHovered && "shadow-2xl"
        )}
      >
        <div className="flex flex-col h-full">
          {/* Logo */}
          <div className="flex items-center h-16 px-3 border-b border-sidebar-border">
            <Link
              href="/dashboard"
              onClick={() => setMobileOpen(false)}
              className="flex items-center justify-center size-10 shrink-0"
            >
              <AppLogo size="sm" variant="inline" iconOnly />
            </Link>

            {/* App name - only visible when expanded */}
            <span 
              className={cn(
                "ml-2 font-bold text-lg bg-gradient-to-r from-foreground to-foreground/70 bg-clip-text text-transparent whitespace-nowrap transition-opacity duration-150",
                isCollapsed ? "opacity-0 w-0 overflow-hidden" : "opacity-100"
              )}
            >
              myEPBuddy
            </span>

            {/* Mobile close button */}
            <Button
              variant="ghost"
              size="icon"
              className="lg:hidden ml-auto -mr-2"
              onClick={() => setMobileOpen(false)}
              aria-label="Close menu"
            >
              <X className="size-5" />
            </Button>
          </div>

          <ScrollArea className="flex-1 py-4">
            {/* Main navigation */}
            <nav className="space-y-1 px-3">
              {filteredNavItems.map((item) => {
                const isActive = pathname === item.href;
                const isLoading = loadingHref === item.href;
                return (
                  <NavItem
                    key={item.href}
                    item={item}
                    isActive={isActive}
                    isLoading={isLoading}
                    isCollapsed={isCollapsed}
                    onClick={() => handleNavClick(item.href)}
                  />
                );
              })}
            </nav>

            <Separator className="my-4 mx-3" />

            {/* Settings label - fixed height to prevent shift */}
            <div className={cn(
              "h-6 flex items-center px-6 mb-1",
              isCollapsed && "opacity-0"
            )}>
              <span className="text-xs font-medium text-muted-foreground whitespace-nowrap">
                Settings
              </span>
            </div>

            {/* Settings navigation */}
            <nav className="space-y-1 px-3">
              {filteredSettingsItems.map((item) => {
                const isActive = pathname === item.href;
                const isLoading = loadingHref === item.href;
                return (
                  <NavItem
                    key={item.href}
                    item={item}
                    isActive={isActive}
                    isLoading={isLoading}
                    isCollapsed={isCollapsed}
                    onClick={() => handleNavClick(item.href)}
                  />
                );
              })}
            </nav>

            <Separator className="my-4 mx-3" />

            {/* Support Link */}
            <nav className="px-3">
              <NavItem
                item={{
                  title: "Support",
                  href: "/support",
                  icon: Heart,
                  roles: ["member", "admin"],
                }}
                isActive={pathname === "/support"}
                isLoading={loadingHref === "/support"}
                isCollapsed={isCollapsed}
                onClick={() => handleNavClick("/support")}
              />
            </nav>
          </ScrollArea>

          {/* Sidebar mode toggle at bottom */}
          <div className="border-t border-sidebar-border p-3">
            <DropdownMenu modal={false} open={isMenuOpen} onOpenChange={setIsMenuOpen}>
              <DropdownMenuTrigger asChild>
                <Button
                  variant="ghost"
                  className={cn(
                    "h-10 text-sidebar-foreground hover:bg-sidebar-accent/50",
                    isCollapsed 
                      ? "w-10 p-0 justify-center" 
                      : "w-full px-3 justify-start gap-3"
                  )}
                  aria-label="Sidebar settings"
                >
                  <ModeIcon className="size-4 shrink-0" />
                  {!isCollapsed && <span className="flex-1 text-left text-sm font-medium">Sidebar</span>}
                </Button>
              </DropdownMenuTrigger>
              <DropdownMenuContent 
                side={isCollapsed ? "right" : "top"} 
                align={isCollapsed ? "end" : "start"}
                sideOffset={8}
                className="w-48 z-50"
              >
                <DropdownMenuLabel>Sidebar Mode</DropdownMenuLabel>
                <DropdownMenuSeparator />
                <DropdownMenuItem
                  onClick={() => handleModeChange("pinned-open")}
                  className="flex items-center gap-2 cursor-pointer"
                >
                  <PanelLeft className="size-4" />
                  <span className="flex-1">Pin open</span>
                  {mode === "pinned-open" && <Check className="size-4" />}
                </DropdownMenuItem>
                <DropdownMenuItem
                  onClick={() => handleModeChange("hover-expand")}
                  className="flex items-center gap-2 cursor-pointer"
                >
                  <PanelLeftOpen className="size-4" />
                  <span className="flex-1">Expand on hover</span>
                  {mode === "hover-expand" && <Check className="size-4" />}
                </DropdownMenuItem>
                <DropdownMenuItem
                  onClick={() => handleModeChange("pinned-closed")}
                  className="flex items-center gap-2 cursor-pointer"
                >
                  <PanelLeftClose className="size-4" />
                  <span className="flex-1">Pin closed</span>
                  {mode === "pinned-closed" && <Check className="size-4" />}
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </div>
      </aside>
    </TooltipProvider>
  );
}
