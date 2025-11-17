import{j as r}from"./iframe-BXD7fudD.js";import{B as D,P as o,S as i,T as N}from"./Button-BWCiYP-u.js";import"./preload-helper-JDnY5PGr.js";const P={title:"Rostoc Design System/Components/Button",component:D,parameters:{layout:"centered",docs:{description:{component:`Button components from the Rostoc design system

Buttons use the Rostoc brand colors and typography styles from Figma.
All button labels should be in UPPERCASE to match the design system.`}}},tags:["autodocs"],argTypes:{variant:{control:"select",options:["primary","secondary","text"],description:"The visual style variant of the button"},disabled:{control:"boolean",description:"Whether the button is disabled"},children:{control:"text",description:"The content to display inside the button"}}},e={args:{variant:"primary",children:"PRIMARY BUTTON"}},t={args:{variant:"secondary",children:"SECONDARY BUTTON"}},a={args:{variant:"text",children:"TEXT BUTTON"}},s={args:{variant:"primary",children:"DISABLED BUTTON",disabled:!0}},n={args:{children:""},render:()=>r.jsxs("div",{className:"flex flex-col gap-4",children:[r.jsx(o,{children:"PRIMARY BUTTON"}),r.jsx(i,{children:"SECONDARY BUTTON"}),r.jsx(N,{children:"TEXT BUTTON"}),r.jsx(o,{disabled:!0,children:"DISABLED PRIMARY"}),r.jsx(i,{disabled:!0,children:"DISABLED SECONDARY"})]})};var c,d,l;e.parameters={...e.parameters,docs:{...(c=e.parameters)==null?void 0:c.docs,source:{originalSource:`{
  args: {
    variant: 'primary',
    children: 'PRIMARY BUTTON'
  }
}`,...(l=(d=e.parameters)==null?void 0:d.docs)==null?void 0:l.source}}};var m,u,p;t.parameters={...t.parameters,docs:{...(m=t.parameters)==null?void 0:m.docs,source:{originalSource:`{
  args: {
    variant: 'secondary',
    children: 'SECONDARY BUTTON'
  }
}`,...(p=(u=t.parameters)==null?void 0:u.docs)==null?void 0:p.source}}};var T,B,y;a.parameters={...a.parameters,docs:{...(T=a.parameters)==null?void 0:T.docs,source:{originalSource:`{
  args: {
    variant: 'text',
    children: 'TEXT BUTTON'
  }
}`,...(y=(B=a.parameters)==null?void 0:B.docs)==null?void 0:y.source}}};var h,S,g;s.parameters={...s.parameters,docs:{...(h=s.parameters)==null?void 0:h.docs,source:{originalSource:`{
  args: {
    variant: 'primary',
    children: 'DISABLED BUTTON',
    disabled: true
  }
}`,...(g=(S=s.parameters)==null?void 0:S.docs)==null?void 0:g.source}}};var x,R,A;n.parameters={...n.parameters,docs:{...(x=n.parameters)==null?void 0:x.docs,source:{originalSource:`{
  args: {
    children: '' // Dummy value, not used in render
  },
  render: () => <div className="flex flex-col gap-4">
      <PrimaryButton>PRIMARY BUTTON</PrimaryButton>
      <SecondaryButton>SECONDARY BUTTON</SecondaryButton>
      <TextButton>TEXT BUTTON</TextButton>
      <PrimaryButton disabled>DISABLED PRIMARY</PrimaryButton>
      <SecondaryButton disabled>DISABLED SECONDARY</SecondaryButton>
    </div>
}`,...(A=(R=n.parameters)==null?void 0:R.docs)==null?void 0:A.source}}};const v=["Primary","Secondary","Text","Disabled","AllVariants"];export{n as AllVariants,s as Disabled,e as Primary,t as Secondary,a as Text,v as __namedExportsOrder,P as default};
