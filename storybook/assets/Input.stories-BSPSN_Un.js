import{r as t,j as s}from"./iframe-DOnzdozc.js";import{I as r}from"./Input-CRcfvMsl.js";import"./preload-helper-JDnY5PGr.js";const N={title:"Rostoc Design System/Components/Input",component:r,parameters:{layout:"centered",docs:{description:{component:`Input components from the Rostoc design system

Inputs use the Rostoc color palette and typography styles from Figma.
Labels should be in UPPERCASE to match the design system.`}}},tags:["autodocs"],argTypes:{type:{control:"select",options:["text","number","email","password"],description:"The type of input field"}}},n={args:{label:"",value:"",onChange:()=>{}},render:()=>{const[e,a]=t.useState("");return s.jsx(r,{label:"MACHINE NAME",value:e,onChange:a,placeholder:"Enter machine name",type:"text"})}},o={args:{label:"",value:"",onChange:()=>{}},render:()=>{const[e,a]=t.useState("");return s.jsx(r,{label:"CAPACITY",value:e,onChange:a,placeholder:"500",type:"number"})}},l={args:{label:"",value:"",onChange:()=>{}},render:()=>{const[e,a]=t.useState("");return s.jsx(r,{label:"EMAIL ADDRESS",value:e,onChange:a,placeholder:"user@example.com",type:"email"})}},u={args:{label:"",value:"",onChange:()=>{}},render:()=>{const[e,a]=t.useState("");return s.jsx(r,{label:"PASSWORD",value:e,onChange:a,placeholder:"Enter password",type:"password"})}},c={args:{label:"",value:"",onChange:()=>{}},render:()=>{const[e,a]=t.useState("Cool Machine");return s.jsx(r,{label:"MACHINE NAME",value:e,onChange:a,type:"text"})}};var p,m,d;n.parameters={...n.parameters,docs:{...(p=n.parameters)==null?void 0:p.docs,source:{originalSource:`{
  args: {
    label: '',
    value: '',
    onChange: () => {} // Dummy values, not used in render
  },
  render: () => {
    const [value, setValue] = useState('');
    return <Input label="MACHINE NAME" value={value} onChange={setValue} placeholder="Enter machine name" type="text" />;
  }
}`,...(d=(m=n.parameters)==null?void 0:m.docs)==null?void 0:d.source}}};var i,g,h;o.parameters={...o.parameters,docs:{...(i=o.parameters)==null?void 0:i.docs,source:{originalSource:`{
  args: {
    label: '',
    value: '',
    onChange: () => {} // Dummy values, not used in render
  },
  render: () => {
    const [value, setValue] = useState('');
    return <Input label="CAPACITY" value={value} onChange={setValue} placeholder="500" type="number" />;
  }
}`,...(h=(g=o.parameters)==null?void 0:g.docs)==null?void 0:h.source}}};var v,C,b;l.parameters={...l.parameters,docs:{...(v=l.parameters)==null?void 0:v.docs,source:{originalSource:`{
  args: {
    label: '',
    value: '',
    onChange: () => {} // Dummy values, not used in render
  },
  render: () => {
    const [value, setValue] = useState('');
    return <Input label="EMAIL ADDRESS" value={value} onChange={setValue} placeholder="user@example.com" type="email" />;
  }
}`,...(b=(C=l.parameters)==null?void 0:C.docs)==null?void 0:b.source}}};var y,S,E;u.parameters={...u.parameters,docs:{...(y=u.parameters)==null?void 0:y.docs,source:{originalSource:`{
  args: {
    label: '',
    value: '',
    onChange: () => {} // Dummy values, not used in render
  },
  render: () => {
    const [value, setValue] = useState('');
    return <Input label="PASSWORD" value={value} onChange={setValue} placeholder="Enter password" type="password" />;
  }
}`,...(E=(S=u.parameters)==null?void 0:S.docs)==null?void 0:E.source}}};var x,A,I;c.parameters={...c.parameters,docs:{...(x=c.parameters)==null?void 0:x.docs,source:{originalSource:`{
  args: {
    label: '',
    value: '',
    onChange: () => {} // Dummy values, not used in render
  },
  render: () => {
    const [value, setValue] = useState('Cool Machine');
    return <Input label="MACHINE NAME" value={value} onChange={setValue} type="text" />;
  }
}`,...(I=(A=c.parameters)==null?void 0:A.docs)==null?void 0:I.source}}};const R=["Text","Number","Email","Password","WithValue"];export{l as Email,o as Number,u as Password,n as Text,c as WithValue,R as __namedExportsOrder,N as default};
