"use client";

import { usePathname } from "next/navigation";

interface PageTransitionProps {
  children: React.ReactNode;
  className?: string;
}

export function PageTransition({ children, className }: PageTransitionProps) {
  const pathname = usePathname();
  
  return (
    <div key={pathname} className={`animate-fade-in w-full flex flex-col items-center ${className || ""}`}>
      {children}
    </div>
  );
}

